import AVFAudio
import Accelerate
import Foundation

/// Reads, caches and decodes an instrument's samples.
///
/// The instruments' samples ship inside the app (see `Instrument`), and are
/// read straight from the bundle. Remote URLs still work, downloaded once and
/// kept in Caches, as the web app keeps them in CacheStorage.
nonisolated struct InstrumentLoader: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    enum LoadError: LocalizedError, Equatable {
        case unreachable
        case unreadable

        var errorDescription: String? {
            "Could not load this instrument. Try again or choose Basic synth (offline)."
        }
    }

    /// Long enough for any note a piece holds. A piano sample's tail beyond
    /// this is inaudible, and keeping it would double the memory a piece needs.
    static let maxSampleSeconds: Double = 8
    private static let fadeSeconds: Double = 0.25
    private static let concurrentDownloads = 6

    private let fetch: Fetch
    private let cacheDirectory: URL?
    /// Bundled samples are decoded where they sit, rather than read into
    /// memory and written back out to a temporary file first. Off with an
    /// injected fetch, which decides for itself what every URL returns.
    private let decodesFilesInPlace: Bool

    init(session: URLSession = .shared, cacheDirectory: URL? = InstrumentLoader.defaultCacheDirectory) {
        self.cacheDirectory = cacheDirectory
        self.decodesFilesInPlace = true
        self.fetch = { url in
            // Bundled samples. A format that isn't bundled throws, which moves
            // on to the next one just as a failed download does.
            if url.isFileURL { return try Data(contentsOf: url) }
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LoadError.unreachable }
            return data
        }
    }

    init(fetch: @escaping Fetch, cacheDirectory: URL? = nil) {
        self.fetch = fetch
        self.cacheDirectory = cacheDirectory
        self.decodesFilesInPlace = false
    }

    static var defaultCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "instruments-v1", directoryHint: .isDirectory)
    }

    /// The samples `instrument` needs to play these notes at these
    /// velocities, or nil for the basic synth, which needs none.
    func load(_ instrument: Instrument, notes: Set<Int>, velocities: ClosedRange<Int>,
              progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> SampleBank? {
        switch instrument {
        case .basic:
            return nil
        case .grand:
            let preset = SamplePreset.splendidGrand(notes: notes, velocities: velocities)
            return try await loadSamples(preset, progress: progress)
        case .electric, .cp80:
            guard let sfzURL = instrument.sfzURL, let baseURL = instrument.sampleBaseURL else { return nil }
            let text = String(decoding: try await cachedData(at: sfzURL), as: UTF8.self)
            let preset = SamplePreset.sfz(text, baseURL: baseURL).limited(toNotes: notes, velocities: velocities)
            return try await loadSamples(preset, progress: progress)
        case .organ:
            return try await loadOrgan(notes: notes, velocities: velocities, progress: progress)
        }
    }

    // MARK: - Fetching

    func cachedData(at url: URL) async throws -> Data {
        let file = cacheFile(for: url)
        if let file, let cached = try? Data(contentsOf: file) { return cached }
        let fetched = try await fetch(url)
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? fetched.write(to: file, options: .atomic)
        }
        return fetched
    }

    func cacheFile(for url: URL) -> URL? {
        guard let cacheDirectory, let host = url.host() else { return nil }
        return cacheDirectory
            .appending(path: host, directoryHint: .isDirectory)
            .appending(path: url.path(percentEncoded: false), directoryHint: .notDirectory)
    }

    /// Every sample `preset` names, fetched and decoded a few at a time.
    func loadSamples(_ preset: SamplePreset,
                     progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> SampleBank {
        let names = preset.sampleNames
        guard !names.isEmpty else { return SampleBank(preset: preset, recordings: [:]) }

        let fetchOne: @Sendable (String) async throws -> (String, SampleBank.Recording?) = { name in
            // The first copy that decodes to its end wins. Failing that, the
            // longest partial one, which at least sounds the note.
            var best: SampleBank.Recording?
            for fileExtension in preset.fileExtensions {
                guard let url = preset.url(for: name, fileExtension: fileExtension) else { continue }
                do {
                    let decoded = decodesFilesInPlace && url.isFileURL
                        ? try Self.decodeReportingCompleteness(fileAt: url)
                        : try Self.decodeReportingCompleteness(try await cachedData(at: url),
                                                               fileExtension: fileExtension)
                    if decoded.complete { return (name, decoded.recording) }
                    if decoded.recording.frames.count > (best?.frames.count ?? 0) { best = decoded.recording }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A copy that will not even open is not kept, so a damaged
                    // download is fetched afresh next time.
                    if let file = cacheFile(for: url) { try? FileManager.default.removeItem(at: file) }
                }
            }
            // smplr carries on without a sample it could not load; so do we.
            return (name, best)
        }

        var recordings: [String: SampleBank.Recording] = [:]
        try await withThrowingTaskGroup(of: (String, SampleBank.Recording?).self) { group in
            var pending = names[...]
            for _ in 0..<Self.concurrentDownloads {
                guard let name = pending.popFirst() else { break }
                group.addTask { try await fetchOne(name) }
            }
            var finished = 0
            for try await (name, recording) in group {
                finished += 1
                progress(Double(finished) / Double(names.count))
                if let recording { recordings[name] = recording }
                if let name = pending.popFirst() {
                    group.addTask { try await fetchOne(name) }
                }
            }
        }
        try Task.checkCancellation()
        guard !recordings.isEmpty else { throw LoadError.unreachable }
        return SampleBank(preset: preset, recordings: recordings)
    }

    private func loadOrgan(notes: Set<Int>, velocities: ClosedRange<Int>,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> SampleBank {
        let source = String(decoding: try await cachedData(at: Instrument.organSoundfontURL), as: UTF8.self)
        let encoded = try SamplePreset.midiJSNotes(source)
        // Without loop points the organ still plays, just without sustaining
        // past its recordings — smplr treats them as optional too.
        let loops = (try? await cachedData(at: Instrument.organLoopsURL)).flatMap { SamplePreset.soundfontLoops($0) }
        let preset = SamplePreset.soundfont(noteNames: Array(encoded.keys), loops: loops)
            .limited(toNotes: notes, velocities: velocities)
        progress(0.5)

        var recordings: [String: SampleBank.Recording] = [:]
        let names = preset.sampleNames
        for (offset, name) in names.enumerated() {
            try Task.checkCancellation()
            if let base64 = encoded[name],
               let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
               let recording = try? Self.decode(data, fileExtension: "mp3") {
                recordings[name] = recording
            }
            progress(0.5 + 0.5 * Double(offset + 1) / Double(names.count))
        }
        guard !recordings.isEmpty || names.isEmpty else { throw LoadError.unreadable }
        return SampleBank(preset: preset, recordings: recordings)
    }

    // MARK: - Decoding

    struct Decoded {
        let recording: SampleBank.Recording
        /// Whether decoding reached the end of the audio, or the length cap,
        /// rather than stopping at damaged data.
        let complete: Bool
    }

    /// Decodes compressed audio to a mono 16-bit recording, at most
    /// `maxSampleSeconds` long.
    static func decode(_ data: Data, fileExtension: String) throws -> SampleBank.Recording {
        try decodeReportingCompleteness(data, fileExtension: fileExtension).recording
    }

    static func decodeReportingCompleteness(_ data: Data, fileExtension: String) throws -> Decoded {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(fileExtension)", directoryHint: .notDirectory)
        try data.write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try decodeReportingCompleteness(fileAt: temporary)
    }

    /// Reads until the audio actually ends rather than trusting the length the
    /// file states, which Ogg files often leave unset, and keeps whatever
    /// decoded before any damaged data. Anything cut short fades out rather
    /// than stopping with a click.
    ///
    /// The work on every frame — mixing to mono, the fade, the conversion to
    /// 16-bit — runs in Accelerate. Done frame by frame in Swift, it took tens
    /// of seconds per instrument in an unoptimized Debug build.
    static func decodeReportingCompleteness(fileAt url: URL) throws -> Decoded {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let rate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let limit = Int((maxSampleSeconds * rate).rounded())
        let chunk: AVAudioFrameCount = 8192
        guard channelCount > 0, rate > 0, limit > 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)
        else { throw LoadError.unreadable }

        // Asked for before reading, as the previous decoder did. Core Audio
        // decodes some Ogg Opus files further once their length has been
        // requested: CP80's 063-D#4-PP.ogg gives 2.98s of audio this way,
        // 1.99s without.
        _ = file.length

        let mono = UnsafeMutableBufferPointer<Float>.allocate(capacity: limit)
        defer { mono.deallocate() }
        var count = 0
        var reachedEnd = false
        var capped = false
        while true {
            do {
                try file.read(into: buffer, frameCount: chunk)
            } catch {
                // Core Audio reports the end of the stream as an error with
                // code 0. Anything else — or an "end" well short of the length
                // the file states — is damaged data.
                let stated = Double(file.length)
                let decoded = Double(count)
                reachedEnd = (error as NSError).code == 0
                    ? stated == 0 || decoded >= stated * 0.9
                    : stated > 0 && decoded >= stated * 0.98
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else {
                reachedEnd = true
                break
            }
            // The channels' average: summed in channel order, then divided.
            let take = min(frames, limit - count)
            let destination = mono.baseAddress! + count
            destination.update(from: channels[0], count: take)
            for channel in 1..<channelCount {
                vDSP_vadd(destination, 1, channels[channel], 1, destination, 1, vDSP_Length(take))
            }
            if channelCount > 1 {
                var divisor = Float(channelCount)
                vDSP_vsdiv(destination, 1, &divisor, destination, 1, vDSP_Length(take))
            }
            count += take
            if count >= limit {
                capped = true
                break
            }
        }
        guard count > 1 else { throw LoadError.unreadable }

        let complete = reachedEnd || capped
        let fadeStart = max(0, count - Int(fadeSeconds * rate))
        let fadeCount = count - fadeStart
        if capped || !complete, fadeCount > 0 {
            // Each frame scaled by its distance from the end: 1 down to 1/n.
            // Plain Swift, unlike the rest: it is at most a quarter-second of
            // frames, and vDSP's arithmetic rounds a few of them a step away
            // from what this has always produced.
            let fadeLength = Float(fadeCount)
            for index in fadeStart..<count {
                mono[index] *= Float(count - index) / fadeLength
            }
        }

        var scale: Float = 32767, low: Float = -32767, high: Float = 32767
        vDSP_vsmul(mono.baseAddress!, 1, &scale, mono.baseAddress!, 1, vDSP_Length(count))
        vDSP_vclip(mono.baseAddress!, 1, &low, &high, mono.baseAddress!, 1, vDSP_Length(count))
        // Rounded as Swift's rounded() rounds, halves away from zero, where
        // vDSP's own rounding sends halves to even. Nudged by just under a half
        // towards each value's sign, then truncated: that matches exactly,
        // where a full half would carry the float just below 0.5 up to 1.
        let nudge = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
        defer { nudge.deallocate() }
        var magnitude = Float(0.5).nextDown, length = Int32(count)
        vDSP_vfill(&magnitude, nudge.baseAddress!, 1, vDSP_Length(count))
        vvcopysignf(nudge.baseAddress!, nudge.baseAddress!, mono.baseAddress!, &length)
        vDSP_vadd(mono.baseAddress!, 1, nudge.baseAddress!, 1, mono.baseAddress!, 1, vDSP_Length(count))
        let frames = [Int16](unsafeUninitializedCapacity: count) { output, initialized in
            vDSP_vfix16(mono.baseAddress!, 1, output.baseAddress!, 1, vDSP_Length(count))
            initialized = count
        }
        return Decoded(recording: SampleBank.Recording(frames: frames, sampleRate: rate), complete: complete)
    }
}
