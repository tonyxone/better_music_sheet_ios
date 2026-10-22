import Foundation

/// The bundled sample every visitor can open and practise with no account and
/// no subscription. Must name the same job as the backend's
/// config.DEMO_JOB_ID, which grants this one job id a read-only carve-out, and
/// the web app's lib/api.ts.
nonisolated enum DemoSheet {
    static let jobID = "demo-ode-to-joy"
    static var title: String { String(localized: "Ode to Joy", bundle: .app) }
    static var detail: String { String(localized: "Beethoven · free, no account needed", bundle: .app) }

    static func isDemo(_ jobID: String) -> Bool { jobID == self.jobID }
}
