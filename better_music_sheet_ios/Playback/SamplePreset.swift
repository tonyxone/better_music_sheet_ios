import Foundation

/// One recorded sample and the keys and dynamics it covers.
///
/// Flattened from smplr's group-and-region layout: a region already carries
/// whatever its SFZ group and global section set, so matching a note needs no
/// hierarchy.
nonisolated struct SampleRegion: Sendable, Hashable {
    var keys: ClosedRange<Int>
    var velocities: ClosedRange<Int> = 0...127
    /// The key the sample was recorded at; the other keys are pitched from it.
    /// Nil plays the sample untransposed.
    var pitch: Int?
    /// Fine tuning, in semitones.
    var tune: Double = 0
    var volumeDB: Double = 0
    /// The sample's path under the preset's base URL without its extension,
    /// or its note name in a soundfont.
    var sample: String
    var ampRelease: Double?
    var cutoffHz: Double?
    /// Loop points in seconds, for instruments that sustain.
    var loop: ClosedRange<Double>?
}

/// One velocity layer of the grand piano.
nonisolated struct PianoLayer: Sendable {
    let velocity: ClosedRange<Int>
    let cutoffHz: Double?
    let samples: [(Int, String)]
}

/// An instrument as smplr describes it: which sample plays for which key and
/// velocity, and how. Ported from smplr 1.0.0, the version the web app uses,
/// so the two apps choose the same recordings and levels for every note.
nonisolated struct SamplePreset: Sendable {
    /// Where samples are fetched from; nil when they arrive embedded.
    var baseURL: URL?
    /// Tried in order. Ogg Opus first, as smplr picks it everywhere but
    /// Safari: dozens of the electric pianos' m4a files are malformed and
    /// stop decoding part-way, while their Ogg copies are whole. m4a stays as
    /// a fallback.
    var fileExtensions = ["ogg", "m4a"]
    var regions: [SampleRegion]
    /// smplr's release when an instrument sets none.
    var ampRelease: Double = 0.3
    /// The instrument's own output level.
    var gain: Double = SamplePreset.channelGain

    /// The web app creates every instrument at smplr volume 85, which smplr
    /// turns into gain the same way it treats velocity.
    static let channelGain = velocityGain(85)

    /// smplr's `midiVelToGain`.
    static func velocityGain(_ velocity: Int) -> Double {
        Double(velocity * velocity) / 16129
    }

    static func gain(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }

    /// Every region that sounds for this key at this velocity, as smplr's
    /// region matcher finds them.
    func matches(midi: Int, velocity: Int) -> [SampleRegion] {
        regions.filter { $0.keys.contains(midi) && $0.velocities.contains(velocity) }
    }

    /// Each sample the regions use, once, in order.
    var sampleNames: [String] {
        var seen = Set<String>()
        return regions.compactMap { seen.insert($0.sample).inserted ? $0.sample : nil }
    }

    func url(for sample: String, fileExtension: String) -> URL? {
        guard let baseURL,
              let path = "\(sample).\(fileExtension)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: baseURL.absoluteString + "/" + path)
    }

    /// Keeps only what a piece can reach, so nothing it never plays is
    /// fetched or held in memory. The regions kept are unchanged, so every note
    /// the piece does play sounds exactly as it would with all of them.
    func limited(toNotes notes: Set<Int>, velocities: ClosedRange<Int>) -> SamplePreset {
        var copy = self
        copy.regions = regions.filter { region in
            region.velocities.overlaps(velocities) && notes.contains { region.keys.contains($0) }
        }
        return copy
    }

    // MARK: - Helpers shared by every instrument

    /// smplr's `spreadKeyRanges`: each sample covers the keys up to halfway
    /// to its neighbours, and the outermost ones reach the ends of MIDI.
    static func spreadKeyRanges(_ samples: [(Int, String)]) -> [(keys: ClosedRange<Int>, pitch: Int, sample: String)] {
        let sorted = samples.sorted { $0.0 < $1.0 }
        return sorted.indices.compactMap { index in
            let midi = sorted[index].0
            let low = index == 0 ? 0 : (sorted[index - 1].0 + midi) / 2 + 1
            let high = index == sorted.count - 1 ? 127 : (midi + sorted[index + 1].0) / 2
            guard low <= high else { return nil }
            return (low...high, midi, sorted[index].1)
        }
    }

    /// smplr's `noteNameToMidi`: "C4" is 60, and flats are written "b".
    static func midi(noteName: String) -> Int? {
        guard let match = noteName.wholeMatch(of: /([a-gA-G])(#+|b+|)(-?\d+)/),
              let letter = match.1.uppercased().unicodeScalars.first,
              let octave = Int(match.3)
        else { return nil }
        let accidentals = match.2
        let alteration = accidentals.first == "b" ? -accidentals.count : accidentals.count
        let step = (Int(letter.value) + 3) % 7
        return [0, 2, 4, 5, 7, 9, 11][step] + alteration + 12 * (octave + 1)
    }

    // MARK: - Grand piano

    static let splendidGrandBaseURL = URL(string: "https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples")!

    /// smplr's `SplendidGrandPiano` as the web app loads it: only the samples
    /// recorded at keys the piece plays, spread across the keyboard, with a
    /// 0.35-second release.
    static func splendidGrand(notes: Set<Int>, velocities: ClosedRange<Int> = 1...127) -> SamplePreset {
        let regions = splendidGrandLayers
            .filter { $0.velocity.overlaps(velocities) }
            .flatMap { layer in
                spreadKeyRanges(layer.samples.filter { notes.contains($0.0) }).map { spread in
                    SampleRegion(keys: spread.keys, velocities: layer.velocity, pitch: spread.pitch,
                                 sample: spread.sample, cutoffHz: layer.cutoffHz)
                }
            }
        return SamplePreset(baseURL: splendidGrandBaseURL, regions: regions, ampRelease: 0.35)
    }

    // MARK: - SFZ

    /// Greg Sullivan's pianos keep samples in `samples/`, named without the
    /// extension the SFZ gives them.
    static func gregSullivanPath(_ name: String) -> String {
        "samples/" + name.replacing(/\.\w+$/, with: "")
    }

    /// smplr's `sfzToPreset`: the opcodes it reads, and nothing else. Anything
    /// smplr ignores — envelopes, pedal curves, controller labels — is ignored
    /// here too, so the instrument sounds as it does on the web.
    static func sfz(_ text: String, baseURL: URL,
                    pathFromSampleName: (String) -> String = gregSullivanPath) -> SamplePreset {
        var mode = "global"
        var global: [String: SFZValue] = [:]
        var group: [String: SFZValue] = [:]
        var current: [String: SFZValue] = [:]
        var regions: [SampleRegion] = []

        func closeScope() {
            switch mode {
            case "global":
                global.merge(current) { $1 }
            case "group":
                group = current
            case "region":
                let merged = global.merging(group) { $1 }.merging(current) { $1 }
                if let region = sfzRegion(merged, group: group, pathFromSampleName: pathFromSampleName) {
                    regions.append(region)
                }
            default:
                break
            }
            current = [:]
        }

        for token in sfzTokens(resolvingDefines(in: text)) {
            switch token {
            case .header(let name):
                closeScope()
                mode = name
                if name == "group" { group = [:] }
            case .property(let key, let value):
                current[key] = value
            }
        }
        closeScope()

        return SamplePreset(baseURL: baseURL, regions: regions)
    }

    enum SFZValue: Sendable, Equatable {
        case number(Double)
        case text(String)

        var number: Double? {
            if case .number(let value) = self { return value }
            return nil
        }
    }

    enum SFZToken: Sendable, Equatable {
        case header(String)
        case property(String, SFZValue)
    }

    private static func sfzRegion(_ props: [String: SFZValue], group: [String: SFZValue],
                                  pathFromSampleName: (String) -> String) -> SampleRegion? {
        guard case .text(let rawSample)? = props["sample"] else { return nil }
        func integer(_ key: String, in source: [String: SFZValue]) -> Int? {
            source[key]?.number.map { Int($0) }
        }

        var keys = 0...127
        var pitch: Int?
        if let key = integer("key", in: props) {
            keys = key...key
            pitch = key
        } else if let low = integer("lokey", in: props), let high = integer("hikey", in: props), low <= high {
            keys = low...high
            pitch = low
        }
        if let center = integer("pitch_keycenter", in: props) { pitch = center }

        var velocities = 0...127
        if let low = integer("lovel", in: props), let high = integer("hivel", in: props), low <= high {
            velocities = low...high
        }
        // smplr checks a note against its group's ranges before the region's.
        if let low = integer("lokey", in: group), let high = integer("hikey", in: group), low <= high {
            guard keys.overlaps(low...high) else { return nil }
            keys = keys.clamped(to: low...high)
        }
        if let low = integer("lovel", in: group), let high = integer("hivel", in: group), low <= high {
            guard velocities.overlaps(low...high) else { return nil }
            velocities = velocities.clamped(to: low...high)
        }

        return SampleRegion(keys: keys,
                            velocities: velocities,
                            pitch: pitch,
                            tune: (props["tune"]?.number ?? 0) / 100,
                            volumeDB: props["volume"]?.number ?? 0,
                            sample: pathFromSampleName(rawSample),
                            ampRelease: props["ampeg_release"]?.number)
    }

    /// smplr's `resolveDefines`: `#define $NAME value` lines are removed and
    /// every `$NAME` replaced.
    static func resolvingDefines(in text: String) -> String {
        var defines: [(String, String)] = []
        var lines: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = trimmed.wholeMatch(of: /#define\s+(\$\w+)\s+(.+)/) {
                defines.append((String(match.1), match.2.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                lines.append(line)
            }
        }
        var result = lines.joined(separator: "\n")
        for (name, value) in defines {
            result = result.replacingOccurrences(of: name, with: value)
        }
        return result
    }

    /// smplr's SFZ tokenizer: headers, and `key=value` pairs whose values run
    /// until the next key.
    static func sfzTokens(_ text: String) -> [SFZToken] {
        var tokens: [SFZToken] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = Substring(rawLine)
            if let comment = line.range(of: "//") { line = line[..<comment.lowerBound] }
            line = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))

            var position = line.startIndex
            while position < line.endIndex {
                while position < line.endIndex, line[position] == " " { position = line.index(after: position) }
                guard position < line.endIndex else { break }

                if line[position] == "<" {
                    guard let close = line[position...].firstIndex(of: ">") else { break }
                    let name = line[line.index(after: position)..<close]
                    tokens.append(.header(name.trimmingCharacters(in: .whitespaces).lowercased()))
                    position = line.index(after: close)
                    continue
                }

                guard let equals = line[position...].firstIndex(of: "=") else { break }
                let key = line[position..<equals].trimmingCharacters(in: .whitespaces)
                let rest = line[line.index(after: equals)...]
                let raw: String
                if let next = rest.firstMatch(of: /\s+\S+=\S/) {
                    raw = rest[..<next.range.lowerBound].trimmingCharacters(in: .whitespaces)
                    position = next.range.lowerBound
                } else {
                    raw = rest.trimmingCharacters(in: .whitespaces)
                    position = line.endIndex
                }
                if !key.isEmpty {
                    // JavaScript's Number(): an empty value is zero.
                    let value: SFZValue = raw.isEmpty ? .number(0) : Double(raw).map(SFZValue.number) ?? .text(raw)
                    tokens.append(.property(key, value))
                }
            }
        }
        return tokens
    }

    // MARK: - Soundfont

    /// smplr's `soundfontToPreset`: one sample per note name, spread across
    /// the keyboard, looping where loop points are known.
    static func soundfont(noteNames: [String], loops: [Int: ClosedRange<Double>]?) -> SamplePreset {
        let entries = noteNames.compactMap { name in midi(noteName: name).map { ($0, name) } }
        let regions = spreadKeyRanges(entries).map { spread in
            SampleRegion(keys: spread.keys, pitch: spread.pitch, sample: spread.sample, loop: loops?[spread.pitch])
        }
        // smplr's Soundfont adds a fixed gain of 5 in front of its output.
        return SamplePreset(baseURL: nil, regions: regions, gain: channelGain * 5)
    }

    enum SoundfontError: Error {
        case notMIDIJS
    }

    /// A MIDI.js soundfont file's notes, each as its base64 audio, parsed the
    /// way smplr's `midiJsToJson` does.
    static func midiJSNotes(_ source: String) throws -> [String: String] {
        guard let header = source.range(of: "MIDI.Soundfont."),
              let equals = source[header.upperBound...].firstIndex(of: "="),
              let lastComma = source.lastIndex(of: ","),
              source.index(equals, offsetBy: 2, limitedBy: source.endIndex).map({ $0 < lastComma }) == true
        else { throw SoundfontError.notMIDIJS }

        let json = source[source.index(equals, offsetBy: 2)..<lastComma] + "}"
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String] else {
            throw SoundfontError.notMIDIJS
        }
        return object.mapValues { value in
            value.firstIndex(of: ",").map { String(value[value.index(after: $0)...]) } ?? value
        }
    }

    /// Loop points keyed by note, converted from frames at 44.1 kHz to
    /// seconds, as smplr's `fetchSoundfontLoopData` does.
    static func soundfontLoops(_ data: Data, sampleRate: Double = 44_100) -> [Int: ClosedRange<Double>]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]] else { return nil }
        var loops: [Int: ClosedRange<Double>] = [:]
        for (name, offsets) in raw {
            guard let midi = midi(noteName: name), offsets.count >= 2, offsets[0] < offsets[1] else { continue }
            loops[midi] = (offsets[0] / sampleRate)...(offsets[1] / sampleRate)
        }
        return loops
    }
}
