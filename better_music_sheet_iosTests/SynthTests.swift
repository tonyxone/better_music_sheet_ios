import Foundation
import Testing
@testable import better_music_sheet_ios

struct SynthVoiceTests {

    @Test func tuningIsConcertPitch() {
        #expect(SynthVoice.frequency(midi: 69) == 440)
        #expect(abs(SynthVoice.frequency(midi: 60) - 261.6256) < 0.001)
        #expect(abs(SynthVoice.frequency(midi: 81) - 880) < 1e-9)
    }

    @Test func velocityScalesThePeak() {
        let loud = SynthVoice.envelope(velocity: 100, duration: 1)
        let soft = SynthVoice.envelope(velocity: 50, duration: 1)
        #expect(abs(loud.peak - 0.9) < 1e-12)
        #expect(soft.peak < loud.peak)
        #expect(abs(loud.sustain - 0.9 * 0.31) < 1e-12)
    }

    @Test func velocityIsClampedToTheMIDIRange() {
        #expect(SynthVoice.envelope(velocity: 500, duration: 1) == SynthVoice.envelope(velocity: 127, duration: 1))
        #expect(SynthVoice.envelope(velocity: -3, duration: 1) == SynthVoice.envelope(velocity: 1, duration: 1))
    }

    @Test func silentBeforeTheNoteStarts() {
        let envelope = SynthVoice.envelope(velocity: 80, duration: 1)
        #expect(SynthVoice.gain(at: -0.01, envelope: envelope) == 0)
    }

    @Test func attackReachesThePeakThenDecaysToSustain() {
        let e = SynthVoice.envelope(velocity: 100, duration: 2)
        #expect(abs(SynthVoice.gain(at: e.attack, envelope: e) - e.peak) < 1e-9)
        #expect(SynthVoice.gain(at: e.attack + e.decay / 2, envelope: e) < e.peak)
        #expect(abs(SynthVoice.gain(at: e.attack + e.decay + 0.1, envelope: e) - e.sustain) < 1e-9)
    }

    @Test func releaseFadesAndThenFallsSilent() {
        let e = SynthVoice.envelope(velocity: 100, duration: 1)
        let atRelease = SynthVoice.gain(at: e.releaseStart, envelope: e)
        let shortlyAfter = SynthVoice.gain(at: e.releaseStart + 0.05, envelope: e)
        #expect(shortlyAfter < atRelease)
        #expect(SynthVoice.gain(at: e.releaseStart + SynthVoice.tailSeconds + 0.001, envelope: e) == 0)
    }

    @Test func aVeryShortNoteStillFinishesItsAttack() {
        // A grace note can be a couple of milliseconds long; releasing before
        // the attack completes would make it a click rather than a note.
        let e = SynthVoice.envelope(velocity: 80, duration: 0.002)
        #expect(e.releaseStart >= e.attack + 0.02)
    }

    @Test func triangleWaveShape() {
        #expect(SynthVoice.triangle(phase: 0) == -1)
        #expect(SynthVoice.triangle(phase: 0.25) == 0)
        #expect(SynthVoice.triangle(phase: 0.5) == 1)
        #expect(SynthVoice.triangle(phase: 0.75) == 0)
        #expect(SynthVoice.triangle(phase: 1.25) == 0)
    }
}

struct SynthMixerTests {
    private let rate = 48_000.0

    private func render(_ mixer: inout SynthMixer, frames: Int, from start: Int64) -> [Float] {
        // Pre-filled so a test would notice a render that fails to overwrite.
        var buffer = [Float](repeating: 1, count: frames)
        buffer.withUnsafeMutableBufferPointer { pointer in
            mixer.render(into: pointer.baseAddress!, frameCount: frames, startingAt: start)
        }
        return buffer
    }

    private func peak(_ samples: [Float]) -> Float { samples.map(abs).max() ?? 0 }
    private func energy(_ samples: [Float]) -> Double { samples.reduce(0) { $0 + Double($1 * $1) } }

    private func note(_ midi: Int, from start: Int64, to end: Int64, velocity: Double = 100) -> SynthNote {
        SynthNote(midi: midi, velocity: velocity, startFrame: start, endFrame: end)
    }

    @Test func nothingScheduledIsSilence() {
        var mixer = SynthMixer(sampleRate: rate)
        #expect(peak(render(&mixer, frames: 512, from: 0)) == 0)
    }

    @Test func silentUntilTheNoteStarts() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(69, from: 4_800, to: 52_800)])

        #expect(peak(render(&mixer, frames: 4_800, from: 0)) == 0)
        #expect(peak(render(&mixer, frames: 4_800, from: 4_800)) > 0.05)
    }

    @Test func fallsSilentAfterTheReleaseTail() {
        // A tenth of a second, rendered in realistic 512-frame blocks well
        // past its release.
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(60, from: 0, to: 4_800)])

        var last: [Float] = []
        var frame: Int64 = 0
        while frame < 24_000 {
            last = render(&mixer, frames: 512, from: frame)
            frame += 512
        }
        #expect(peak(last) == 0)
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test func aChordIsLouderThanOneOfItsNotes() {
        var single = SynthMixer(sampleRate: rate)
        single.load([note(60, from: 0, to: 96_000)])
        var chord = SynthMixer(sampleRate: rate)
        chord.load([note(60, from: 0, to: 96_000), note(64, from: 0, to: 96_000), note(67, from: 0, to: 96_000)])

        // Half a second in, during the sustain.
        let one = energy(render(&single, frames: 4_800, from: 24_000))
        let three = energy(render(&chord, frames: 4_800, from: 24_000))
        #expect(three > one * 2)
    }

    @Test func unsortedNotesStillPlay() {
        // If the schedule were not sorted on load, the late note first in the
        // list would block the early one from ever starting.
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(72, from: 9_600, to: 20_000), note(60, from: 0, to: 9_600)])
        #expect(peak(render(&mixer, frames: 4_800, from: 0)) > 0.05)
    }

    @Test func silenceStopsEverythingAtOnce() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(60, from: 0, to: 96_000)])
        _ = render(&mixer, frames: 4_800, from: 0)
        #expect(mixer.activeVoiceCount == 1)

        mixer.silence()
        #expect(mixer.activeVoiceCount == 0)
        #expect(peak(render(&mixer, frames: 4_800, from: 4_800)) == 0)
    }

    @Test func loadingReplacesTheOldSchedule() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(60, from: 0, to: 96_000)])
        _ = render(&mixer, frames: 4_800, from: 0)

        mixer.load([note(67, from: 48_000, to: 96_000)])
        // The first note is gone; the new one has not started yet.
        #expect(peak(render(&mixer, frames: 4_800, from: 4_800)) == 0)
    }

    @Test func aNoteThatAlreadyEndedIsSkipped() {
        // Loaded late, a note whose release finished before this block would
        // only produce a click.
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load([note(60, from: 0, to: 480)])
        #expect(peak(render(&mixer, frames: 512, from: 48_000)) == 0)
        #expect(mixer.activeVoiceCount == 0)
    }

    @Test func outputStaysWithinFullScale() {
        var mixer = SynthMixer(sampleRate: rate)
        mixer.load((36..<96).map { note($0, from: 0, to: 96_000, velocity: 127) })
        let samples = render(&mixer, frames: 4_800, from: 100)
        #expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test func renderingIsDeterministic() {
        var first = SynthMixer(sampleRate: rate)
        var second = SynthMixer(sampleRate: rate)
        first.load([note(61, from: 100, to: 30_000)])
        second.load([note(61, from: 100, to: 30_000)])
        #expect(render(&first, frames: 2_048, from: 1_000) == render(&second, frames: 2_048, from: 1_000))
    }
}
