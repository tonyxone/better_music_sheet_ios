import Foundation

/// Getting a file to the backend.
///
/// Two paths, chosen the way the web app chooses them. The serverless backend
/// hands out a presigned S3 form so the bytes never pass through the API; an
/// older deployment answers 404 to that and takes a plain multipart post
/// instead. Supporting both means the app keeps working across a backend
/// cutover rather than breaking for everyone mid-deploy.
nonisolated struct SheetUploader: Sendable {

    struct Reservation: Decodable, Sendable {
        struct Upload: Decodable, Sendable {
            let url: String
            let fields: [String: String]
        }
        let jobID: String
        let upload: Upload

        private enum CodingKeys: String, CodingKey {
            case jobID = "jobId"
            case upload
        }
    }

    private struct LegacyResponse: Decodable, Sendable {
        let jobID: String
        private enum CodingKeys: String, CodingKey { case jobID = "jobId" }
    }

    private struct ReservationRequest: Encodable, Sendable {
        let filename: String
        let size: Int
        let contentType: String
        let style: String
        let octave: Bool
        let fontSize: Double
        let dpi: Int?
        let autoRetry: Bool
        let labelColor: String

        private enum CodingKeys: String, CodingKey {
            case filename, size, style, octave, dpi
            case contentType = "content_type"
            case fontSize = "font_size"
            case autoRetry = "auto_retry"
            case labelColor = "label_color"
        }
    }

    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// Uploads a file and returns the new job's id.
    func upload(filename: String, data: Data, options: AnnotationOptions) async throws -> String {
        guard data.count <= AppConfig.maxUploadBytes else {
            throw APIError.http(status: 413, detail: "That file is larger than \(AppConfig.maxUploadBytes / 1024 / 1024) MB.")
        }
        let contentType = Self.contentType(for: filename)

        let reservation: Reservation
        do {
            reservation = try await client.post("/api/uploads", body: ReservationRequest(
                filename: filename, size: data.count, contentType: contentType,
                style: options.style.rawValue, octave: options.octave,
                fontSize: options.fontSize, dpi: options.dpi, autoRetry: options.autoRetry,
                labelColor: options.labelColor))
        } catch let error as APIError where error.isNotFound {
            return try await legacyUpload(filename: filename, data: data,
                                          contentType: contentType, options: options)
        }

        guard let url = URL(string: reservation.upload.url) else { throw APIError.invalidURL }

        var form = MultipartForm()
        for (name, value) in reservation.upload.fields {
            form.addField(name: name, value: value)
        }
        // S3 ignores anything after the file part, so it goes last.
        form.addFile(name: "file", filename: filename, contentType: contentType, data: data)

        do {
            try await client.postExternal(url, body: form.encoded(), contentType: form.contentType)
        } catch {
            throw APIError.transport("The file upload failed. Please try again — an unfinished upload expires after 15 minutes.")
        }

        // Completion only speeds up how quickly the job appears. S3's own
        // notification and the backend's reconciler own delivery, so a
        // failure here is not worth surfacing.
        try? await client.send("/api/uploads/\(reservation.jobID)/complete", method: "POST")
        return reservation.jobID
    }

    private func legacyUpload(filename: String, data: Data,
                              contentType: String, options: AnnotationOptions) async throws -> String {
        var form = MultipartForm()
        form.addFile(name: "file", filename: filename, contentType: contentType, data: data)
        form.addField(name: "style", value: options.style.rawValue)
        form.addField(name: "octave", value: String(options.octave))
        form.addField(name: "font_size", value: String(options.fontSize))
        form.addField(name: "auto_retry", value: String(options.autoRetry))
        form.addField(name: "label_color", value: options.labelColor)
        if let dpi = options.dpi { form.addField(name: "dpi", value: String(dpi)) }

        let (body, _) = try await client.call("/api/sheets", method: "POST",
                                              body: form.encoded(), contentType: form.contentType)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LegacyResponse.self, from: body).jobID
    }

    static func contentType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        default: "application/octet-stream"
        }
    }

    static func isSupported(filename: String) -> Bool {
        ["pdf", "jpg", "jpeg", "png"].contains((filename as NSString).pathExtension.lowercased())
    }
}
