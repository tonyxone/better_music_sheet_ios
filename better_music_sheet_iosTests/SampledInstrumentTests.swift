import AVFAudio
import Foundation
import Testing
@testable import better_music_sheet_ios

struct SamplePresetTests {

    @Test func noteNamesMatchSmplr() {
        #expect(SamplePreset.midi(noteName: "C4") == 60)
        #expect(SamplePreset.midi(noteName: "A0") == 21)
        #expect(SamplePreset.midi(noteName: "Bb0") == 22)
        #expect(SamplePreset.midi(noteName: "D#0") == 15)
        #expect(SamplePreset.midi(noteName: "B-1") == 11)
        #expect(SamplePreset.midi(noteName: "H4") == nil)
    }

    @Test func samplesSpreadHalfwayToTheirNeighbours() {
        let spread = SamplePreset.spreadKeyRanges([(28, "c"), (21, "a"), (24, "b")])
        #expect(spread.map(\.keys) == [0...22, 23...26, 27...127])
        #expect(spread.map(\.pitch) == [21, 24, 28])
        #expect(spread.map(\.sample) == ["a", "b", "c"])
    }

    @Test func theGrandPianoUsesOnlySamplesAtKeysThePiecePlays() throws {
        let preset = SamplePreset.splendidGrand(notes: [23, 27])
        #expect(Set(preset.regions.compactMap(\.pitch)) == [23, 27])
        #expect(preset.ampRelease == 0.35)

        // 25 is exactly halfway, so it takes the lower sample, as smplr's
        // spread does; the softest layer is darkened with a filter.
        let quiet = preset.matches(midi: 25, velocity: 20)
        #expect(quiet.map(\.sample) == ["PP B-1"])
        #expect(quiet.first?.cutoffHz == 1000)

        let loud = try #require(preset.matches(midi: 26, velocity: 120).first)
        #expect(loud.pitch == 27)
        #expect(loud.cutoffHz == nil)

        #expect(preset.fileExtensions == ["ogg", "m4a"])
        #expect(preset.url(for: "PP B-1", fileExtension: "ogg")?.absoluteString
                == "https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples/PP%20B-1.ogg")
    }

    @Test func velocitiesAPieceNeverReachesLoadNothing() {
        let preset = SamplePreset.splendidGrand(notes: [23], velocities: 90...100)
        #expect(preset.regions.map(\.velocities) == [85...100])
    }

    private static let sfz = """
    //midi cc
    #define $RELEASE 72
    #define $EXT flac

    <control>
    default_path=Samples/
    label_cc$RELEASE=Release

    <global>
    ampeg_attack=0.001
    ampeg_release_oncc$RELEASE=2

    <group>
    lovel=1
    hivel=37
    group_label=pp
    <region> region_label=01 lokey=33 hikey=35 pitch_keycenter=33 volume=-3.2 sample=a1pp.$EXT tune=-5
    <region> region_label=06 lokey=060 hikey=062 pitch_keycenter=061 volume=-6 sample=061-C#4-PP.$EXT

    <group>
    lovel=38
    hivel=127
    <region> lokey=33 hikey=62 sample=a1mp.$EXT ampeg_release=1.5
    """

    @Test func readsAnSFZTheWaySmplrDoes() throws {
        let preset = SamplePreset.sfz(Self.sfz, baseURL: URL(string: "https://example.com/wurlitzer")!)
        #expect(preset.regions.count == 3)
        #expect(preset.ampRelease == 0.3)

        let first = preset.regions[0]
        #expect(first.keys == 33...35)
        #expect(first.pitch == 33)
        #expect(first.velocities == 1...37)
        #expect(first.volumeDB == -3.2)
        #expect(first.tune == -5.0 / 100)
        #expect(first.sample == "samples/a1pp")
        #expect(first.ampRelease == nil)

        let second = preset.regions[1]
        #expect(second.keys == 60...62)
        #expect(second.pitch == 61)
        #expect(second.sample == "samples/061-C#4-PP")
        #expect(preset.url(for: second.sample, fileExtension: "m4a")?.absoluteString
                == "https://example.com/wurlitzer/samples/061-C%234-PP.m4a")

        let third = preset.regions[2]
        #expect(third.velocities == 38...127)
        #expect(third.pitch == 33)
        #expect(third.ampRelease == 1.5)
        #expect(third.volumeDB == 0)

        #expect(preset.matches(midi: 61, velocity: 20).map(\.sample) == ["samples/061-C#4-PP"])
        #expect(preset.matches(midi: 61, velocity: 90).map(\.sample) == ["samples/a1mp"])
    }

    @Test func limitingToAPieceKeepsOnlyReachableRegions() {
        let preset = SamplePreset.sfz(Self.sfz, baseURL: URL(string: "https://example.com")!)
            .limited(toNotes: [61], velocities: 1...20)
        #expect(preset.sampleNames == ["samples/061-C#4-PP"])
    }

    @Test func readsAMIDIJSSoundfontAndItsLoops() throws {
        let source = """
        if (typeof(MIDI) === 'undefined') var MIDI = {};
        MIDI.Soundfont.church_organ = {
        "A0": "data:audio/mp3;base64,QUJD",
        "C4": "data:audio/mp3;base64,REVG",
        }
        """
        let notes = try SamplePreset.midiJSNotes(source)
        #expect(notes == ["A0": "QUJD", "C4": "REVG"])

        let loops = SamplePreset.soundfontLoops(Data(#"{"C4": [44100, 88200], "nope": [1, 2]}"#.utf8))
        #expect(loops == [60: 1.0...2.0])

        let preset = SamplePreset.soundfont(noteNames: Array(notes.keys), loops: loops)
        #expect(preset.gain == SamplePreset.channelGain * 5)
        #expect(preset.matches(midi: 40, velocity: 64).first?.sample == "A0")
        let high = try #require(preset.matches(midi: 50, velocity: 64).first)
        #expect(high.sample == "C4")
        #expect(high.loop == 1.0...2.0)
    }
}

struct SampleBankTests {

    @Test func pitchesAndLevelsAStrikeLikeSmplr() throws {
        let preset = SamplePreset(baseURL: nil,
                                  regions: [SampleRegion(keys: 0...127, pitch: 60, tune: 0.1, volumeDB: -6, sample: "s")],
                                  ampRelease: 0.3, gain: 1)
        let bank = SampleBank(preset: preset, recordings: ["s": .init(frames: [0, 1000, 2000], sampleRate: 44_100)])

        let strike = try #require(bank.strikes(midi: 62, velocity: 100.4, outputRate: 48_000).first)
        #expect(abs(strike.step - pow(2, 2.1 / 12) * 44_100 / 48_000) < 1e-9)
        #expect(abs(strike.gain - (100.0 * 100 / 16129) * pow(10, -6.0 / 20)) < 1e-12)
        #expect(strike.ampRelease == 0.3)
    }

    @Test func aSampleThatFailedToLoadIsSkipped() {
        let preset = SamplePreset(baseURL: nil, regions: [SampleRegion(keys: 0...127, pitch: 60, sample: "missing")])
        let bank = SampleBank(preset: preset, recordings: [:])
        #expect(bank.strikes(midi: 60, velocity: 80, outputRate: 48_000).isEmpty)
    }
}

struct SampledMixerTests {
    private let rate = 48_000.0

    private func bank(frames: [Int16], loop: ClosedRange<Double>? = nil, cutoffHz: Double? = nil,
                      keys: ClosedRange<Int> = 0...127) -> SampleBank {
        let preset = SamplePreset(baseURL: nil,
                                  regions: [SampleRegion(keys: keys, pitch: 60, sample: "s", cutoffHz: cutoffHz, loop: loop)],
                                  ampRelease: 0.1, gain: 1)
        return SampleBank(preset: preset, recordings: ["s": .init(frames: frames, sampleRate: rate)])
    }

    private func render(_ mixer: inout SynthMixer, frames: Int, from start: Int64) -> [Float] {
        var buffer = [Float](repeating: 0, count: frames)
        buffer.withUnsafeMutableBufferPointer { pointer in
            mixer.render(into: pointer.baseAddress!, frameCount: frames, startingAt: start)
        }
        return buffer
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    private let halfScale = [Int16](repeating: 16_384, count: 48_000)

    @Test func aSampleSoundsFromItsStartAtItsLevel() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: halfScale))
        mixer.load([SynthNote(midi: 60, velocity: 127, startFrame: 4_800, endFrame: 24_000)])

        #expect(peak(render(&mixer, frames: 4_800, from: 0)) == 0)
        let playing = render(&mixer, frames: 480, from: 9_600)
        // Half scale, at full velocity, through the master level: under the
        // limiter's knee, so exactly that.
        #expect(abs(playing[100] - 0.5 * 0.65) < 0.001)
    }

    @Test func releaseFadesLinearlyToSilence() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: halfScale))
        mixer.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 9_600)])

        _ = render(&mixer, frames: 9_600, from: 0)
        // Halfway through the 0.1-second release.
        let fading = render(&mixer, frames: 1, from: 12_000)
        #expect(abs(fading[0] - 0.5 * 0.65 * 0.5) < 0.001)

        let after = render(&mixer, frames: 4_800, from: 14_400)
        #expect(peak(after) == 0)
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test func anUnloopedSampleEndsWithItsRecording() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: [Int16](repeating: 16_384, count: 1_000)))
        mixer.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000)])

        #expect(peak(render(&mixer, frames: 900, from: 0)) > 0.1)
        #expect(peak(render(&mixer, frames: 512, from: 1_000)) == 0)
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test func aLoopedSampleSustainsWhileHeld() {
        var mixer = SynthMixer(sampleRate: rate)
        let loop = (200.0 / rate)...(800.0 / rate)
        mixer.setBank(bank(frames: [Int16](repeating: 16_384, count: 1_000), loop: loop))
        mixer.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000)])

        _ = render(&mixer, frames: 1_024, from: 0)
        #expect(peak(render(&mixer, frames: 512, from: 20_000)) > 0.1)
    }

    @Test func thePitchIsShiftedFromTheRecordedKey() {
        // A ramp makes the read position visible: an octave up reads twice as fast.
        let ramp = (0..<4_000).map { Int16($0) }
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: ramp))
        mixer.load([SynthNote(midi: 72, velocity: 127, startFrame: 0, endFrame: 48_000)])

        let out = render(&mixer, frames: 1_000, from: 0)
        let expected = Float(2 * 500) / 32_768 * 0.65
        #expect(abs(out[500] - expected) < 0.0005)
    }

    @Test func theSoftestLayerIsDarkened() {
        // Alternating samples: all energy at the top of the spectrum.
        let buzz = (0..<48_000).map { $0 % 2 == 0 ? Int16(16_384) : Int16(-16_384) }

        var plain = SynthMixer(sampleRate: rate)
        plain.setBank(bank(frames: buzz))
        plain.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000)])

        var filtered = SynthMixer(sampleRate: rate)
        filtered.setBank(bank(frames: buzz, cutoffHz: 1_000))
        filtered.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000)])

        let open = peak(render(&plain, frames: 1_024, from: 0))
        let dark = peak(Array(render(&filtered, frames: 1_024, from: 0).dropFirst(512)))
        #expect(dark < open * 0.05)
    }

    @Test func aKeyNoSampleCoversIsSilent() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: halfScale, keys: 0...10))
        mixer.load([SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000)])
        #expect(peak(render(&mixer, frames: 1_024, from: 0)) == 0)
    }

    @Test func aLoudChordStaysUnderFullScale() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.setBank(bank(frames: halfScale))
        mixer.load((0..<8).map { _ in SynthNote(midi: 60, velocity: 127, startFrame: 0, endFrame: 48_000) })
        let out = render(&mixer, frames: 1_024, from: 0)
        #expect(peak(out) < 1)
        #expect(peak(out) > 0.9)
    }
}

struct InstrumentLoaderTests {

    private actor Counter {
        private(set) var requests: [URL] = []
        func record(_ url: URL) { requests.append(url) }
    }

    /// A stereo WAV at 44.1 kHz: 0.5 on the left, 0.25 on the right.
    private static func wav(seconds: Double) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let rate = 44_100.0
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                                           AVSampleRateKey: rate,
                                           AVNumberOfChannelsKey: 2,
                                           AVLinearPCMBitDepthKey: 16,
                                           AVLinearPCMIsFloatKey: false]
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let frames = AVAudioFrameCount(rate * seconds)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
            buffer.frameLength = frames
            for index in 0..<Int(frames) {
                buffer.floatChannelData![0][index] = 0.5
                buffer.floatChannelData![1][index] = 0.25
            }
            try file.write(from: buffer)
        }
        return try Data(contentsOf: url)
    }

    @Test func decodesToMonoAndCapsTheLength() throws {
        let rate = 44_100.0
        let recording = try InstrumentLoader.decode(try Self.wav(seconds: 10), fileExtension: "wav")
        #expect(recording.sampleRate == rate)
        #expect(recording.frames.count == Int(rate * InstrumentLoader.maxSampleSeconds))
        // The two channels averaged.
        #expect(abs(Int(recording.frames[1_000]) - 12_288) <= 3)
        // Cut short, so it fades out rather than stopping with a click.
        #expect(abs(Int(recording.frames.last!)) < 200)
    }

    @Test func fetchesOnceThenReadsTheCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let loader = InstrumentLoader(fetch: { url in
            await counter.record(url)
            return Data("<region> sample=a.flac".utf8)
        }, cacheDirectory: directory)

        let url = URL(string: "https://example.com/pianos/Wurlitzer%20EP200.sfz")!
        let first = try await loader.cachedData(at: url)
        let second = try await loader.cachedData(at: url)
        #expect(first == second)
        #expect(await counter.requests == [url])
        #expect(loader.cacheFile(for: url)?.lastPathComponent == "Wurlitzer EP200.sfz")
    }

    @Test func fallsBackToTheNextFormatWhenOneWillNotLoad() async throws {
        let counter = Counter()
        let wav = try Self.wav(seconds: 0.5)
        let loader = InstrumentLoader(fetch: { url in
            await counter.record(url)
            guard url.pathExtension == "wav" else { throw URLError(.badServerResponse) }
            return wav
        })
        var preset = SamplePreset(baseURL: URL(string: "https://example.com")!,
                                  regions: [SampleRegion(keys: 0...127, pitch: 60, sample: "c4")])
        preset.fileExtensions = ["ogg", "wav"]

        let bank = try await loader.loadSamples(preset)
        #expect(bank.recordings.count == 1)
        #expect(await counter.requests.map(\.lastPathComponent) == ["c4.ogg", "c4.wav"])
    }

    @Test func theBasicSynthDownloadsNothing() async throws {
        let counter = Counter()
        let loader = InstrumentLoader(fetch: { url in
            await counter.record(url)
            return Data()
        })
        let bank = try await loader.load(.basic, notes: [60], velocities: 1...127)
        #expect(bank == nil)
        #expect(await counter.requests.isEmpty)
    }

    @Test func anInstrumentThatCannotBeReachedFails() async {
        let loader = InstrumentLoader(fetch: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: InstrumentLoader.LoadError.unreachable) {
            // 23 is a key every layer has a recording for.
            _ = try await loader.load(.grand, notes: [23], velocities: 1...127)
        }
    }
}
