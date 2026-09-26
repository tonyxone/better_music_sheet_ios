import CoreGraphics
import Foundation
import Testing
@testable import better_music_sheet_ios

/// The same cases as the web app's tests/annotations.test.mjs, so both
/// clients read and write a shared edits document the same way.
struct NoteNameTests {
    @Test func noteNamesParseWithEitherAccidentalSpellingAndAnOptionalOctave() {
        #expect(NoteNames.parse("B♭") == SpelledPitch(step: 6, alter: -1, octave: nil))
        #expect(NoteNames.parse("c#4") == SpelledPitch(step: 0, alter: 1, octave: 4))
        #expect(NoteNames.parse("F𝄪") == SpelledPitch(step: 3, alter: 2, octave: nil))
        #expect(NoteNames.parse("G?") == SpelledPitch(step: 4, alter: 0, octave: nil))
        #expect(NoteNames.parse("bb") == SpelledPitch(step: 6, alter: -1, octave: nil))
        #expect(NoteNames.parse("hello") == nil)
        #expect(NoteNames.parse("") == nil)
    }

    @Test func aRetypedNameMovesToTheNearestStaffPosition() {
        #expect(NoteNames.retypedMIDI(newText: "C", oldText: "B", oldMIDI: 59) == 60)
        #expect(NoteNames.retypedMIDI(newText: "B", oldText: "C", oldMIDI: 60) == 59)
        #expect(NoteNames.retypedMIDI(newText: "E♭", oldText: "E", oldMIDI: 64) == 63)
        #expect(NoteNames.retypedMIDI(newText: "G♭", oldText: "F♯", oldMIDI: 66) == 66)
        #expect(NoteNames.retypedMIDI(newText: "A2", oldText: "C", oldMIDI: 60) == 45)
        #expect(NoteNames.retypedMIDI(newText: "xyz", oldText: "C", oldMIDI: 60) == nil)
    }

    @Test func labelsJSONKeepsGoodItemsAndDropsBrokenOnes() throws {
        let set = try #require(LabelSet.decode(Data(#"""
        {"version": 1, "color": "#1F5FBF", "items": [
          {"id": "1-0-0", "group": "1-0", "page": 1, "x": 10.5, "y": 20, "size": 6.5, "text": "C", "notes": ["n1"]},
          {"id": "broken", "page": "one"}
        ]}
        """#.utf8)))
        #expect(set.color == "#1F5FBF")
        #expect(set.items == [LabelItem(id: "1-0-0", group: "1-0", page: 1, x: 10.5, y: 20, size: 6.5, text: "C", notes: ["n1"])])
        #expect(LabelSet.decode(Data(#"{"items": []}"#.utf8)) == nil)
    }

    @Test func roundsHalvesUpLikeJavaScript() {
        #expect(PDFLabelReader.jsRound(2.5) == 3)
        #expect(PDFLabelReader.jsRound(-2.5) == -2)
        #expect(PDFLabelReader.jsRound(3408.4) == 3408)
    }

    @Test func aWebIDShiftedByATrailingSpaceFindsItsName() {
        func item(_ id: String) -> LabelItem {
            LabelItem(id: id, group: id, page: 1, x: 0, y: 0, size: 6.5, text: "E", notes: [])
        }
        let set = LabelSet(color: "#000000", items: [item("pdf-1-3408-3048"), item("pdf-1-3300-3048"), item("pdf-1-4510-3048")])
        let adopted = set.adoptingIDs(of: ["pdf-1-3425-3048", "pdf-1-4510-3048", "pdf-2-100-100"])
        // The nearest name to its left on the same baseline takes the web's id;
        // one already matching keeps its own; one with no neighbour is left alone.
        #expect(adopted.items.map(\.id) == ["pdf-1-3425-3048", "pdf-1-3300-3048", "pdf-1-4510-3048"])
        #expect(set.adoptingIDs(of: ["pdf-1-3408-3048"]) == set)
    }
}

func editingTimeline() throws -> Timeline {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Timeline.self, from: Data("""
    {
      "version": 1, "tempo_bpm_default": 96, "total_beats": 16,
      "measures": [
        {"index": 0, "label": "1", "page": 1, "start_beat": 4, "length_beats": 4,
         "bbox_pt": null, "distinct_midis": [60]}
      ],
      "notes": [
        {"source_id": "s1", "printed_id": "n1", "measure_index": 0, "role": 0, "hand": "right",
         "midi": 60, "start_beat": 5, "duration_beats": 1, "is_grace": false, "bbox_pt": null},
        {"source_id": "s1b", "printed_id": "n1", "measure_index": 0, "role": 0, "hand": "right",
         "midi": 60, "start_beat": 13, "duration_beats": 1, "is_grace": false, "bbox_pt": null}
      ]
    }
    """.utf8))
}

let linkedLabel = LabelItem(id: "L1", group: "L1", page: 1, x: 0, y: 0, size: 6.5, text: "C", notes: ["n1"])

struct SheetEditsTests {
    @Test func retypingALinkedNameWritesACorrectionKeepingTimingAndHand() throws {
        let result = try #require(SheetEdits.correctionsForRetype(linkedLabel, to: "D", original: editingTimeline(), corrections: [:]))
        #expect(result.linked)
        #expect(result.changed == 1)
        #expect(result.corrections["n1"] == NoteCorrection(midi: 62, hand: .right, offset: 1, duration: 1))
    }

    @Test func retypingBackToThePrintedNameRemovesTheCorrection() throws {
        let timeline = try editingTimeline()
        let corrected = try #require(SheetEdits.correctionsForRetype(linkedLabel, to: "D", original: timeline, corrections: [:]))
        let back = try #require(SheetEdits.correctionsForRetype(linkedLabel, to: "C", original: timeline, corrections: corrected.corrections))
        #expect(back.corrections["n1"] == nil)
    }

    @Test func textThatIsNotANoteNameLeavesPlaybackAlone() throws {
        let timeline = try editingTimeline()
        #expect(SheetEdits.correctionsForRetype(linkedLabel, to: "slow", original: timeline, corrections: [:]) == nil)
        let unlinked = LabelItem(id: "L2", group: "L2", page: 1, x: 0, y: 0, size: 6.5, text: "C", notes: [])
        #expect(SheetEdits.correctionsForRetype(unlinked, to: "D", original: timeline, corrections: [:])?.linked == false)
    }

    @Test func storedEditsAreSanitizedEntryByEntry() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"""
        {"version": 1,
         "labels": {"a": {"dx": 2, "dy": "x", "text": "D"}, "b": {"nonsense": true}, "c": {"hidden": true}},
         "texts": [{"id": "t", "page": 1, "x": 1, "y": 2, "text": "hi", "size": 10, "color": "#112233"}, {"id": "bad"}],
         "strokes": [{"id": "s", "page": 1, "tool": "pen", "color": "#000000", "width": 1, "points": [0, 0, 1, 1]},
                     {"id": "s2", "page": 1, "tool": "laser", "color": "#000000", "width": 1, "points": [0, 0]}],
         "corrections": {"n1": {"midi": 62, "hand": null, "offset": 0, "duration": 1}, "n2": {"midi": 999}}}
        """#.utf8))
        let doc = SheetEdits(json: json)
        #expect(Set(doc.labels.keys) == ["a", "c"])
        #expect(doc.labels["a"] == SheetEdits.LabelEdit(dx: 2, dy: nil, text: "D", hidden: false))
        #expect(doc.texts.count == 1)
        #expect(doc.strokes.count == 1)
        #expect(Array(doc.corrections.keys) == ["n1"])
        #expect(SheetEdits(json: nil) == .empty)
    }

    @Test func theDocumentRoundTripsThroughTheWireFormat() throws {
        var doc = SheetEdits()
        doc.labels["L1"] = SheetEdits.LabelEdit(dx: 1.5, dy: nil, text: "D♭", hidden: false)
        doc.texts = [SheetEdits.TextNote(id: "t", page: 2, x: 1, y: 2, text: "slower\nhere", size: 10, color: "#c0392b")]
        doc.strokes = [SheetEdits.Stroke(id: "s", page: 1, tool: .highlighter, color: "#ffd84d", width: 7, points: [0, 0, 5, 5])]
        doc.corrections["n1"] = NoteCorrection(midi: 61, hand: nil, offset: 0.5, duration: 1)

        let data = try JSONSerialization.data(withJSONObject: doc.jsonObject)
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(raw["version"] as? Int == 1)
        // The web app refuses a correction whose hand is missing rather than null.
        let correction = try #require((raw["corrections"] as? [String: Any])?["n1"] as? [String: Any])
        #expect(correction["hand"] is NSNull)
        #expect(SheetEdits(json: raw) == doc)
    }

    @Test func aLabelResolvesToItsMovedRetypedOrHiddenForm() {
        var doc = SheetEdits()
        doc.labels["L1"] = SheetEdits.LabelEdit(dx: 3, dy: -1, text: "D")
        let item = LabelItem(id: "L1", group: "L1", page: 1, x: 10, y: 20, size: 6.5, text: "C", notes: [])
        let moved = doc.resolve(item)
        #expect(moved?.x == 13)
        #expect(moved?.y == 19)
        #expect(moved?.text == "D")
        doc.labels["L1"] = SheetEdits.LabelEdit(hidden: true)
        #expect(doc.resolve(item) == nil)
    }

    @Test func strokeThinningKeepsTheEndsAndTheCorners() {
        var line: [Double] = []
        for i in 0...50 { line += [Double(i), 0] }
        for i in 1...50 { line += [50, Double(i)] }
        let thin = Ink.simplify(line)
        #expect(thin == [0, 0, 50, 0, 50, 50])
        #expect(Ink.segments(thin) == [.move(0, 0), .quad(cx: 50, cy: 0, x: 50, y: 25), .line(50, 50)])
    }

    @Test func aSelectionOfNamesNotesAndDrawingsMovesTogether() {
        var before = SheetEdits()
        before.labels["L1"] = SheetEdits.LabelEdit(dx: 1, text: "D")
        before.texts = [
            SheetEdits.TextNote(id: "t1", page: 1, x: 10, y: 20, text: "hi", size: 10, color: "#000000"),
            SheetEdits.TextNote(id: "t2", page: 1, x: 50, y: 50, text: "stay", size: 10, color: "#000000"),
        ]
        before.strokes = [SheetEdits.Stroke(id: "s1", page: 2, tool: .pen, color: "#000000", width: 1, points: [0, 0, 4, 4])]
        let moved = before.moving([
            SelectedItem(kind: .label, id: "L1"), SelectedItem(kind: .label, id: "L2"),
            SelectedItem(kind: .text, id: "t1"), SelectedItem(kind: .stroke, id: "s1"),
        ], dx: 2, dy: -3)
        #expect(moved.labels["L1"] == SheetEdits.LabelEdit(dx: 3, dy: -3, text: "D"))
        #expect(moved.labels["L2"] == SheetEdits.LabelEdit(dx: 2, dy: -3))
        #expect(moved.texts[0].x == 12 && moved.texts[0].y == 17)
        #expect(moved.texts[1].x == 50)
        #expect(moved.strokes[0].points == [2, -3, 6, 1])
        #expect(before.texts[0].x == 10)
    }
}

@MainActor
struct SheetEditsStoreTests {
    private let base = URL(string: "https://api.example.com")!

    private func store(_ channel: StubProtocol.Channel, defaults: UserDefaults) -> SheetEditsStore {
        let client = APIClient(baseURL: base, urlSession: channel.session(),
                               sessions: SessionStore(store: InMemorySecretStore()),
                               guestID: GuestID(store: InMemorySecretStore()))
        return SheetEditsStore(jobID: "job1", client: client, defaults: defaults,
                               saveDelay: .seconds(3600), retryDelay: .seconds(3600))
    }

    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    private func addText(_ store: SheetEditsStore, _ text: String = "hi") {
        store.update { d in
            var next = d
            next.texts.append(SheetEdits.TextNote(id: "t-\(text)", page: 1, x: 0, y: 0, text: text, size: 10, color: "#000000"))
            return next
        }
    }

    @Test func savesAgainstTheRevisionItLoaded() async throws {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"revision": 4, "doc": null}"#.utf8)),
            .init(body: Data(#"{"revision": 5, "updated_at": 1}"#.utf8)),
        ])
        let edits = store(channel, defaults: freshDefaults())
        await edits.load()
        addText(edits)
        #expect(edits.canUndo)
        await edits.flush()

        #expect(edits.saveState == .saved)
        let put = try #require(channel.recorded.last)
        #expect(put.httpMethod == "PUT")
        #expect(put.url?.path() == "/api/sheets/job1/edits")
        let body = try #require(put.httpBodyStream.map(readAll) ?? put.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["revision"] as? Int == 4)
    }

    @Test func aConflictAdoptsTheOtherDevicesCopy() async throws {
        let channel = StubProtocol.Channel([
            .init(body: Data(#"{"revision": 1, "doc": null}"#.utf8)),
            .init(status: 409, body: Data(#"""
            {"detail": "These edits changed in another window.", "revision": 2,
             "doc": {"version": 1, "texts": [{"id": "theirs", "page": 1, "x": 1, "y": 1, "text": "theirs", "size": 10, "color": "#000000"}]}}
            """#.utf8)),
        ])
        let edits = store(channel, defaults: freshDefaults())
        await edits.load()
        addText(edits, "mine")
        await edits.flush()

        #expect(edits.doc?.texts.map(\.id) == ["theirs"])
        #expect(!edits.canUndo)
        #expect(edits.notice != nil)
    }

    @Test func aFailedSaveLeavesADraftThatWinsOnTheNextOpen() async throws {
        let defaults = freshDefaults()
        let failing = StubProtocol.Channel([
            .init(body: Data(#"{"revision": 3, "doc": null}"#.utf8)),
            .init(status: 500, body: Data(#"{"detail": "boom"}"#.utf8)),
        ])
        let first = store(failing, defaults: defaults)
        await first.load()
        addText(first, "offline")
        await first.flush()
        #expect(first.saveState == .error)

        let reopened = store(StubProtocol.Channel([.init(body: Data(#"{"revision": 3, "doc": null}"#.utf8))]), defaults: defaults)
        await reopened.load()
        #expect(reopened.doc?.texts.map(\.text) == ["offline"])
        #expect(reopened.saveState == .unsaved)

        // Against a newer server copy, the draft is stale and dropped.
        let moved = store(StubProtocol.Channel([.init(body: Data(#"{"revision": 9, "doc": null}"#.utf8))]), defaults: defaults)
        await moved.load()
        #expect(moved.doc == .empty)
    }

    @Test func undoAndRedoWalkTheHistory() async {
        let edits = store(StubProtocol.Channel([.init(body: Data(#"{"revision": 0, "doc": null}"#.utf8))]), defaults: freshDefaults())
        await edits.load()
        addText(edits, "a")
        addText(edits, "b")
        edits.undo()
        #expect(edits.doc?.texts.map(\.text) == ["a"])
        edits.redo()
        #expect(edits.doc?.texts.map(\.text) == ["a", "b"])
    }

    private func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
struct SheetEditorModelTests {
    private func editor(labels: [LabelItem] = [linkedLabel]) async throws -> SheetEditorModel {
        let channel = StubProtocol.Channel([.init(body: Data(#"{"revision": 0, "doc": null}"#.utf8))])
        let client = APIClient(baseURL: URL(string: "https://api.example.com")!, urlSession: channel.session(),
                               sessions: SessionStore(store: InMemorySecretStore()),
                               guestID: GuestID(store: InMemorySecretStore()))
        let store = SheetEditsStore(jobID: "job1", client: client, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    saveDelay: .seconds(3600))
        await store.load()
        let model = SheetEditorModel(store: store, labels: LabelSet(color: "#000000", items: labels),
                                     timeline: try editingTimeline())
        model.isEditing = true
        return model
    }

    private let named = LabelItem(id: "L1", group: "g", page: 1, x: 100, y: 100, size: 6.5, text: "C", notes: ["n1"])

    @Test func tappingANameSelectsItAndTappingAgainOpensItForRetyping() async throws {
        let model = try await editor(labels: [named])
        model.tap(at: CGPoint(x: 100, y: 97), page: 1, pxPerPt: 2)
        #expect(model.selection == [SelectedItem(kind: .label, id: "L1")])
        model.tap(at: CGPoint(x: 100, y: 97), page: 1, pxPerPt: 2)
        #expect(model.textEditor?.initialText == "C")

        model.closeTextEditor("D")
        #expect(model.doc.labels["L1"]?.text == "D")
        #expect(model.doc.corrections["n1"]?.midi == 62)
        #expect(model.notice == "Playback now plays D.")
    }

    @Test func draggingASelectedNameMovesItAsOneUndoStep() async throws {
        let model = try await editor(labels: [named])
        let start = CGPoint(x: 100, y: 97)
        #expect(model.claimsPan(at: start, page: 1, pxPerPt: 2))
        #expect(!model.claimsPan(at: CGPoint(x: 400, y: 400), page: 1, pxPerPt: 2))
        model.beginPan(at: start, page: 1, pxPerPt: 2)
        model.movePan(to: CGPoint(x: 104, y: 99), page: 1, pxPerPt: 2)
        model.endPan(at: CGPoint(x: 110, y: 97))
        #expect(model.doc.labels["L1"] == SheetEdits.LabelEdit(dx: 10, dy: 0))
        model.store.undo()
        #expect(model.doc.labels.isEmpty)
    }

    @Test func drawingAddsAThinnedStroke() async throws {
        let model = try await editor()
        model.tool = .pen
        model.beginPan(at: CGPoint(x: 0, y: 0), page: 2, pxPerPt: 1)
        for x in 1...20 { model.movePan(to: CGPoint(x: Double(x), y: 0), page: 2, pxPerPt: 1) }
        model.endPan(at: CGPoint(x: 20, y: 0))
        let stroke = try #require(model.doc.strokes.first)
        #expect(stroke.page == 2 && stroke.tool == .pen && stroke.points == [0, 0, 20, 0])
        #expect(model.draft == nil)
    }

    @Test func anEmptyNewTextNoteLeavesNothingBehind() async throws {
        let model = try await editor()
        model.tool = .text
        model.tap(at: CGPoint(x: 50, y: 50), page: 1, pxPerPt: 1)
        #expect(model.textEditor?.isNew == true)
        model.closeTextEditor("  ")
        #expect(model.doc.texts.isEmpty)
        #expect(!model.store.canUndo)

        model.tap(at: CGPoint(x: 50, y: 50), page: 1, pxPerPt: 1)
        model.closeTextEditor("breathe\n")
        #expect(model.doc.texts.map(\.text) == ["breathe"])
        model.store.undo()
        #expect(model.doc.texts.isEmpty)
    }

    @Test func aBoxSelectsWhatsInsideAndResetClearsNames() async throws {
        let other = LabelItem(id: "L2", group: "g", page: 1, x: 300, y: 300, size: 6.5, text: "E", notes: [])
        let model = try await editor(labels: [named, other])
        #expect(model.beginMarquee(at: CGPoint(x: 50, y: 50), page: 1, pxPerPt: 1))
        model.moveMarquee(to: CGPoint(x: 150, y: 150))
        model.endMarquee()
        #expect(model.selection == [SelectedItem(kind: .label, id: "L1")])

        model.deleteSelection()
        #expect(model.doc.labels["L1"]?.hidden == true)
        model.reset(.names)
        #expect(model.doc.labels.isEmpty)
        model.undoReset()
        #expect(model.doc.labels["L1"]?.hidden == true)
    }

    @Test func recoloringChangesNamesNotesAndDrawingsAndTheSheetColourClearsIt() async throws {
        let model = try await editor(labels: [named])
        model.store.update { d in
            var next = d
            next.texts = [SheetEdits.TextNote(id: "t", page: 1, x: 300, y: 300, text: "hi", size: 10, color: "#000000")]
            next.strokes = [SheetEdits.Stroke(id: "s", page: 1, tool: .pen, color: "#000000", width: 1.2, points: [0, 0, 5, 5])]
            return next
        }
        model.select([SelectedItem(kind: .label, id: "L1"), SelectedItem(kind: .text, id: "t"), SelectedItem(kind: .stroke, id: "s")])
        #expect(model.selectionColor == "#000000")
        model.recolorSelection("#c0392b")
        #expect(model.doc.labels["L1"]?.color == "#c0392b")
        #expect(model.doc.texts[0].color == "#c0392b")
        #expect(model.doc.strokes[0].color == "#c0392b")
        #expect(model.doc.resolve(named)?.color == "#c0392b")
        #expect(model.selectionColor == "#c0392b")

        model.recolorSelection("#000000")
        #expect(model.doc.labels["L1"] == nil)

        // The colour survives the trip through the shared document.
        model.recolorSelection("#1f5fbf")
        let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: model.doc.jsonObject))
        #expect(SheetEdits(json: json).labels["L1"]?.color == "#1f5fbf")
    }

    @Test func namesArentSelectableOnTheOriginalView() async throws {
        let model = try await editor(labels: [named])
        model.tap(at: CGPoint(x: 100, y: 97), page: 1, pxPerPt: 2)
        model.showsNames = false
        #expect(model.selection.isEmpty)
        model.tap(at: CGPoint(x: 100, y: 97), page: 1, pxPerPt: 2)
        #expect(model.selection.isEmpty)
    }
}
