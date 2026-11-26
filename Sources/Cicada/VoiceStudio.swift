import Foundation

/// The local VoiceStudio app's HTTP API (AGPL, a separate process): clone a voice from a recording
/// and speak with it. No VoiceStudio code is bundled or copied; only these HTTP calls cross over,
/// the same pattern as CanCut (an external AGPL process behind an API). VoiceStudio has to be
/// running for any of this to work: its server is http://127.0.0.1:3900 (no auth, loopback only).
enum VoiceStudio {
    /// The voice base a fresh install points at: VoiceStudio's OpenAI-compatible `/v1`.
    static let defaultBase = URL(string: "http://127.0.0.1:3900/v1")!

    enum Failure: Error {
        case http(Int)
        case noID
    }

    /// The API root for the profile calls (`/profiles`, not `/v1/audio/speech`): the voice base
    /// minus its trailing `/v1`.
    static func root(from voiceBase: URL?) -> URL? {
        guard var root = voiceBase else { return nil }
        if root.lastPathComponent == "v1" { root.deleteLastPathComponent() }
        return root
    }

    /// Whether this failure means the server isn't there (the app isn't running), rather than a
    /// refusal: only then is "VoiceStudio belum jalan" the honest notice.
    static func isDown(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut,
                .notConnectedToInternet].contains(urlError.code)
    }

    /// Create a clone profile from a recording and its transcript (`POST /profiles`,
    /// kind=clone). The transcript must be sent: without it the server tries to transcribe the
    /// clip itself, which fails when no speech-to-text model is installed (HTTP 500). Returns the
    /// profile id, which is then the `voice` for `/v1/audio/speech`.
    static func createClone(root: URL, audioURL: URL, text: String) async throws -> String {
        let audio: Data
        do { audio = try Data(contentsOf: audioURL) } catch { throw error }
        let boundary = "BEO-VoiceStudio-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("name", "Suara saya (BEO)")
        field("kind", "clone")
        field("ref_text", text)
        field("language", "Auto")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"ref_audio\"; filename=\"reference.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var req = URLRequest(url: root.appendingPathComponent("profiles"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String, !id.isEmpty else { throw Failure.noID }
        return id
    }

    /// Delete a clone profile. Best effort: a stale id must never block the next recording.
    static func deleteClone(root: URL, id: String) async {
        var req = URLRequest(url: root.appendingPathComponent("profiles/\(id)"))
        req.httpMethod = "DELETE"
        req.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: req)
    }
}
