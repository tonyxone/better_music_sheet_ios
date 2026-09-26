import Foundation

/// The editor's copy of one sheet's edits: undo and redo, and saving shortly
/// after each change. Mirrors the web app's useSheetEdits (lib/edits.ts), and
/// talks to the same endpoint, so changes made here show up there and back.
///
/// A save refused because another device saved first adopts that copy rather
/// than overwriting it. A save that fails outright is kept as a local draft
/// and retried, and a draft still based on what the server holds wins over
/// it on the next open — so an edit made offline isn't lost.
@MainActor
@Observable
final class SheetEditsStore {
    enum SaveState: Sendable, Equatable {
        case saved, saving, unsaved, offline, error

        var message: String {
            switch self {
            case .saved: "All changes saved"
            case .saving, .unsaved: "Saving…"
            case .offline: "Offline — changes will save when you reconnect"
            case .error: "Couldn't save yet — retrying"
            }
        }
    }

    private(set) var doc: SheetEdits?
    private(set) var loadError: String?
    private(set) var saveState: SaveState = .saved
    var notice: String?
    private(set) var canUndo = false
    private(set) var canRedo = false

    let jobID: String
    private let client: APIClient
    private let defaults: UserDefaults
    private let saveDelay: Duration
    private let retryDelay: Duration

    private var revision = 0
    private var past: [SheetEdits] = []
    private var future: [SheetEdits] = []
    private var dirty = false
    private var inFlight = false
    private var timer: Task<Void, Never>?

    private static let historyLimit = 100

    init(jobID: String, client: APIClient = .shared, defaults: UserDefaults = .standard,
         saveDelay: Duration = .seconds(1), retryDelay: Duration = .seconds(8)) {
        self.jobID = jobID
        self.client = client
        self.defaults = defaults
        self.saveDelay = saveDelay
        self.retryDelay = retryDelay
    }

    private var draftKey: String { "sheet-edits-draft:\(jobID)" }

    // MARK: - Loading

    /// This reader's saved edits for the sheet, read-only — for practice
    /// mode, which applies them but never changes them. A pending draft
    /// counts, so a correction made offline still plays.
    static func fetch(jobID: String, client: APIClient = .shared, defaults: UserDefaults = .standard) async throws -> SheetEdits {
        let store = SheetEditsStore(jobID: jobID, client: client, defaults: defaults)
        return try await store.fetchStored().doc
    }

    func load() async {
        guard doc == nil else { return }
        do {
            let (rev, loaded, isDraft) = try await fetchStored()
            revision = rev
            doc = loaded
            loadError = nil
            if isDraft {
                dirty = true
                saveState = .unsaved
                schedule()
            }
        } catch {
            loadError = "Couldn't load your saved changes. \((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func fetchStored() async throws -> (revision: Int, doc: SheetEdits, isDraft: Bool) {
        let (data, _) = try await client.call("/api/sheets/\(jobID)/edits")
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rev = JSONValue.int(body["revision"]) ?? 0
        // An unsaved draft from a visit that went offline, still based on
        // what the server holds, wins over it; one based on anything older
        // is stale.
        if let draft = storedDraft() {
            if draft.base == rev { return (rev, draft.doc, true) }
            defaults.removeObject(forKey: draftKey)
        }
        return (rev, SheetEdits(json: body["doc"]), false)
    }

    private func storedDraft() -> (base: Int, doc: SheetEdits)? {
        guard let data = defaults.data(forKey: draftKey),
              let draft = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = JSONValue.int(draft["base"]) else { return nil }
        return (base, SheetEdits(json: draft["doc"]))
    }

    private func storeDraft(_ doc: SheetEdits) {
        let draft: [String: Any] = ["base": revision, "doc": doc.jsonObject]
        if let data = try? JSONSerialization.data(withJSONObject: draft) {
            defaults.set(data, forKey: draftKey)
        }
    }

    // MARK: - Changing

    /// Apply a change. `transient` changes (a drag in progress) update the
    /// page without an undo step; the gesture's final call records one, from
    /// `before` — the state the gesture started from.
    func update(transient: Bool = false, before: SheetEdits? = nil, _ change: (SheetEdits) -> SheetEdits) {
        guard let current = doc else { return }
        let next = change(current)
        // A gesture that changed things transiently records its undo step at
        // the end, even when that last call has nothing further to change.
        if next == current && (before == nil || before == current) { return }
        if transient {
            doc = next
            return
        }
        past.append(before ?? current)
        if past.count > Self.historyLimit { past.removeFirst() }
        future = []
        commit(next)
    }

    func undo() {
        guard let current = doc, let previous = past.popLast() else { return }
        future.append(current)
        commit(previous)
    }

    func redo() {
        guard let current = doc, let next = future.popLast() else { return }
        past.append(current)
        commit(next)
    }

    private func commit(_ next: SheetEdits) {
        doc = next
        canUndo = !past.isEmpty
        canRedo = !future.isEmpty
        dirty = true
        saveState = .unsaved
        storeDraft(next)
        schedule()
    }

    // MARK: - Saving

    private func schedule(after delay: Duration? = nil) {
        timer?.cancel()
        let wait = delay ?? saveDelay
        timer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            self.timer = nil
            await self.save()
        }
    }

    /// Saves now if anything is waiting — also called when the screen goes
    /// away or the app leaves the foreground.
    func flush() async {
        timer?.cancel()
        timer = nil
        await save()
    }

    func save() async {
        guard dirty, !inFlight, let sending = doc else { return }
        inFlight = true
        dirty = false
        saveState = .saving
        defer {
            inFlight = false
            // Changes made while this save was on the wire go out next.
            if dirty && timer == nil { schedule() }
        }
        do {
            let payload: [String: Any] = ["revision": revision, "doc": sending.jsonObject]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (data, http) = try await client.response("/api/sheets/\(jobID)/edits", method: "PUT",
                                                         body: body, contentType: "application/json")
            let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if http.statusCode == 409 {
                // Another window or device saved first: show that version
                // rather than overwrite it.
                revision = JSONValue.int(answer["revision"]) ?? 0
                doc = SheetEdits(json: answer["doc"])
                past = []
                future = []
                canUndo = false
                canRedo = false
                dirty = false
                defaults.removeObject(forKey: draftKey)
                notice = "These edits were changed on another device, so that version is shown now."
                saveState = .saved
                return
            }
            try client.check(http, data)
            revision = JSONValue.int(answer["revision"]) ?? revision + 1
            // A draft is only good against the revision it was based on.
            if dirty, let doc { storeDraft(doc) } else { defaults.removeObject(forKey: draftKey) }
            saveState = dirty ? .unsaved : .saved
        } catch {
            dirty = true
            if let doc { storeDraft(doc) }
            if case .some(.transport) = error as? APIError {
                saveState = .offline
            } else {
                saveState = .error
            }
            if case .some(.http(413, let detail?)) = error as? APIError { notice = detail }
            schedule(after: retryDelay)
        }
    }
}
