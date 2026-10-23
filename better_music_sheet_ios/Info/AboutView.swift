import SwiftUI

/// What the app does and what it cannot do — the web's About page, for the
/// app.
struct AboutView: View {
    var body: some View {
        InfoPageLayout(title: "About") {
            InfoText.note("What this does, and what it cannot do")

            InfoText.paragraph("Reading sheet music means turning a dot on a line into a note name, and then into a key under your finger. Experienced players stop noticing that step. Everyone else is doing arithmetic in the middle of a piece.")
            InfoText.paragraph("Better Sheet Music does that step for you. Add a PDF or a photo of piano music and you get the same score back with every note labelled, plus a practice mode that lights the notes up on a keyboard as they sound.")

            InfoText.heading("What the labels mean")
            InfoText.paragraph("Each notehead is labelled with its letter name — C, F♯, B♭ — printed close enough to be read at playing distance without burying the notation underneath. Notes that sound together are grouped, so a chord reads as one label rather than a stack of them.")
            InfoText.paragraph("You can switch between sharp and flat spellings, add octave numbers if you are learning where middle C sits, and set the label size to suit how far away the music sits. Instead of letters, the names can also show as jianpu numbers (1 2 3) or solfège (do re mi), switched at any time while reading or practising.")

            InfoText.heading("How it works")
            InfoText.paragraph("Recognition uses [Audiveris](https://github.com/Audiveris/audiveris), an open-source optical music recognition engine. It finds staves, clefs, key signatures and noteheads, and works out each note's pitch. Better Sheet Music then draws the labels onto a copy of your sheet and builds a timeline for playback. Your file is processed on Better Sheet Music's own servers; it is not sent to a third-party service.")
            InfoText.paragraph("Pages that come back badly recognised are automatically retried at a higher resolution, which helps with dense engraving and with photos.")

            InfoText.heading("What it struggles with")
            InfoText.paragraph("Optical music recognition is genuinely hard, and it is better to know the limits than to be surprised by them:")
            InfoText.bullet("**Photos** work, but a flat, evenly lit, straight-on shot works far better than one at an angle. A real PDF is always best.")
            InfoText.bullet("**Handwritten music** is mostly beyond it.")
            InfoText.bullet("**Dense passages** — fast runs, tight ledger lines, heavy ornamentation — lose notes more often than plain writing does.")
            InfoText.bullet("**Playback rhythm is an approximation.** Where a time signature cannot be read, timing is guessed, and the result may drift.")
            InfoText.paragraph("Check the output against the original before you rely on it. It is a reading aid, not a proofreader.")

            InfoText.heading("Cost and accounts")
            InfoText.paragraph("Trying the built-in sample needs no account. Adding your own sheet music needs one, so your sheets are there wherever you sign in — on iPhone, iPad or the website. The free plan keeps one sheet at a time, each upload takes a short ad, and it shows ads; Premium keeps as many sheets as you like, with no ads. One Premium subscription covers the app and the website.")

            InfoText.heading("Getting in touch")
            InfoText.paragraph("Corrections, bug reports, and sheets it read badly are all welcome at [bettermusicsheet@gmail.com](mailto:bettermusicsheet@gmail.com). A sheet that comes out wrong is genuinely useful to see.")

            InfoText.note("Version \(Self.version)")
                .padding(.top, 8)
        }
    }

    /// "1.2 (6)": the release and its build.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let release = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String else { return release }
        return "\(release) (\(build))"
    }
}

#Preview {
    NavigationStack { AboutView() }
}
