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
    // The same hosts smplr loads from, so both apps play the same recordings.

    private static let gregSullivanPianos = "https://smpldsnds.github.io/sfzinstruments-greg-sullivan-e-pianos"

    /// The SFZ file describing an electric piano's samples.
    var sfzURL: URL? {
        switch self {
        case .electric: URL(string: "\(Self.gregSullivanPianos)/wurlitzer-ep200/Wurlitzer%20EP200.sfz")
        case .cp80: URL(string: "\(Self.gregSullivanPianos)/cp80/CP80.sfz")
        default: nil
        }
    }

    /// Where an electric piano's sample paths are resolved from.
    var sampleBaseURL: URL? {
        switch self {
        case .electric: URL(string: "\(Self.gregSullivanPianos)/wurlitzer-ep200")
        case .cp80: URL(string: "\(Self.gregSullivanPianos)/cp80")
        default: nil
        }
    }

    /// FluidR3 GM's church organ as a MIDI.js soundfont. MP3 rather than Ogg,
    /// which is what smplr picks on Safari too.
    static let organSoundfontURL = URL(string: "https://gleitz.github.io/midi-js-soundfonts/FluidR3_GM/church_organ-mp3.js")!
    /// Loop points that let an organ note sustain for as long as it is held.
    static let organLoopsURL = URL(string: "https://goldst.dev/midi-js-soundfonts/FluidR3_GM/church_organ-loop.json")!
}
