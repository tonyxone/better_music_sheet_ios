import Foundation

/// The sounds playback can use, matching the web app's app/play/synth.ts
/// list, in its order and with its names.
nonisolated enum Instrument: String, CaseIterable, Identifiable, Sendable {
    case grand, electric, cp80, organ, basic

    /// The web app's own default.
    static let standard = Instrument.grand
    /// The web app's localStorage key, reused so the name means the same thing.
    static let storageKey = "sheet-instrument"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .grand: "Grand piano"
        case .electric: "Electric piano · Wurlitzer"
        case .cp80: "Electric grand · CP80"
        case .organ: "Church organ"
        case .basic: "Basic synth (offline)"
        }
    }

    /// An organ has no sustain pedal, so the pedal tails a piano rings
    /// through are trimmed off its notes.
    var usesPianoPedal: Bool { self != .organ }

    // MARK: - Where the samples live
    //
    // Bundled with the app: a copy of the web app's own public/instrument-samples,
    // laid out the same way, so both apps play the same recordings and every
    // instrument works offline from the first launch.

    static let samplesDirectory = Bundle.main.url(forResource: "InstrumentSamples", withExtension: "bundle")
        ?? Bundle.main.bundleURL.appending(path: "InstrumentSamples.bundle", directoryHint: .isDirectory)

    /// The SFZ file describing an electric piano's samples.
    var sfzURL: URL? {
        switch self {
        case .electric: Self.samplesDirectory.appending(path: "wurlitzer/wurlitzer-ep200.sfz")
        case .cp80: Self.samplesDirectory.appending(path: "cp80/CP80.sfz")
        default: nil
        }
    }

    /// Where an electric piano's sample paths are resolved from.
    var sampleBaseURL: URL? {
        switch self {
        case .electric: Self.samplesDirectory.appending(path: "wurlitzer")
        case .cp80: Self.samplesDirectory.appending(path: "cp80")
        default: nil
        }
    }

    /// FluidR3 GM's church organ as a MIDI.js soundfont, with MP3 samples.
    static let organSoundfontURL = samplesDirectory.appending(path: "organ/church_organ.js")
    /// Loop points that let an organ note sustain for as long as it is held.
    static let organLoopsURL = samplesDirectory.appending(path: "organ/church_organ-loop.json")
}
