import Foundation

/// Fetching a finished sheet's two artifacts.
///
/// The backend hands out credentials first (`/assets`) and the bytes come
/// from S3 directly, so our Authorization / X-Guest-Id headers never travel
/// to another origin. The 404 fallback exists because the asset endpoint
/// post-dates the streaming ones and a deployed backend may not have it yet
/// (mirrors the web app's lib/sheet-files.ts).
nonisolated enum SheetArtifact: Sendable {
    case pdf, timeline

    var legacyPath: String {
        switch self {
        case .pdf: "download?inline=1"
        case .timeline: "timeline"
        }
    }
}

nonisolated struct SheetAssets: Codable, Sendable {
    let direct: Bool
    let pdf: String?
    let timeline: String?

    func url(for artifact: SheetArtifact) -> String? {
        switch artifact {
        case .pdf: pdf
        case .timeline: timeline
        }
    }
}

nonisolated struct SheetFiles: Sendable {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func data(jobID: String, artifact: SheetArtifact) async throws -> Data {
        let assets: SheetAssets
        do {
            assets = try await client.get("/api/sheets/\(jobID)/assets")
        } catch let error as APIError where error.isNotFound {
            let (data, _) = try await client.call("/api/sheets/\(jobID)/\(artifact.legacyPath)")
            return data
        }

        guard let location = assets.url(for: artifact) else {
            throw APIError.http(status: 404, detail: "That file isn't available for this sheet.")
        }

        if assets.direct {
            guard let url = URL(string: location) else { throw APIError.invalidURL }
            return try await client.fetchExternal(url)
        }
        let (data, _) = try await client.call(location)
        return data
    }

    func timeline(jobID: String) async throws -> Timeline {
        let raw = try await data(jobID: jobID, artifact: .timeline)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Timeline.self, from: raw)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
