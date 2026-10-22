import Foundation

/// One event from the Club relay (docs/contract.md §5).
struct ClubEvent: Codable, Equatable {
    var seq: Int
    var type: String // boom, react, why, join
    var boom: String? // nil for join
    var ts: Double
    var emoji: String?
    var text: String?
    var from: String?
}

struct RelayError: LocalizedError {
    var status: Int
    var body: String
    var errorDescription: String? {
        switch status {
        case 401: "The Club didn't recognise you. Leave the Club and join it again."
        case 403: "That Boom isn't yours, so you can't justify it."
        case 404: "There's no Club with that code, or that Boom never reached it."
        case 409: "That name is already taken in this Club. Pick another."
        case 429: "Too many people joined this Club in the last hour. Try again later."
        default: "The relay answered \(status): \(body.prefix(200))"
        }
    }
}

/// The Club relay client. The Club code and token live in UserDefaults.
enum Relay {
    // ponytail: the token sits in UserDefaults, not the Keychain; it can only post to one small Club
    static var club: String? { UserDefaults.standard.string(forKey: "Club") }
    private static var token: String? { UserDefaults.standard.string(forKey: "Token") }

    /// `defaults write no.panter.lunte RelayURL …` wins over Info.plist `LunteRelayURL`.
    static var base: URL {
        let s = UserDefaults.standard.string(forKey: "RelayURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "LunteRelayURL") as? String ?? ""
        return URL(string: s) ?? URL(string: "http://localhost:8787")!
    }

    static func createClub() async throws -> String {
        struct Created: Decodable { var club: String }
        return try JSONDecoder().decode(Created.self, from: await call("POST", "clubs")).club
    }

    /// Joins and stores the Club code and token.
    static func join(_ club: String, name: String) async throws {
        struct Joined: Decodable { var token: String }
        let joined = try JSONDecoder().decode(Joined.self, from: await call("POST", "clubs/\(club)/join", body: ["name": name]))
        UserDefaults.standard.set(club, forKey: "Club")
        UserDefaults.standard.set(joined.token, forKey: "Token")
    }

    static func leave() {
        UserDefaults.standard.removeObject(forKey: "Club")
        UserDefaults.standard.removeObject(forKey: "Token")
    }

    /// A boom, react or why. Does nothing outside a Club.
    static func post(_ event: [String: Any]) async throws {
        guard let club else { return }
        _ = try await call("POST", "clubs/\(club)/events", body: event, auth: true)
    }

    static func events(after seq: Int) async throws -> [ClubEvent] {
        struct Page: Decodable { var events: [ClubEvent] }
        guard let club else { return [] }
        let data = try await call("GET", "clubs/\(club)/events", query: [URLQueryItem(name: "after", value: String(seq))], auth: true)
        return try JSONDecoder().decode(Page.self, from: data).events
    }

    private static func call(_ method: String, _ path: String, body: [String: Any]? = nil,
                             query: [URLQueryItem] = [], auth: Bool = false) async throws -> Data {
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw RelayError(status: status, body: String(decoding: data, as: UTF8.self)) }
        return data
    }
}
