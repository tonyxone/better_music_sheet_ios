import Foundation

/// A `multipart/form-data` body, built in the order fields are added.
///
/// Order is not incidental here: an S3 presigned POST ignores everything that
/// follows the `file` part, so the file must be added LAST or the upload is
/// rejected with a policy error that says nothing about ordering.
nonisolated struct MultipartForm: Sendable {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func encoded() -> Data {
        var finished = body
        finished.append("--\(boundary)--\r\n")
        return finished
    }
}

nonisolated private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
