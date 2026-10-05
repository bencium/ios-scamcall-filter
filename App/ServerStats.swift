import Foundation

/// What the Details screen shows from the server, fetched each time the app opens. The server
/// can't see which calls it blocked; the blocked-call counts come from the Mac's call report,
/// which the Mac uploads when it runs.
struct ServerStats: Decodable {
    struct Server: Decodable {
        let started: Date
    }

    struct CallsChecked: Decodable {
        let last24h: Int
        let last7d: Int
        let last: Date?
    }

    struct MacNotes: Decodable {
        struct Database: Decodable {
            let numbers: Int
            let prefixes: [String]
        }

        struct OfcomCheck: Decodable {
            let at: Date
            let result: String
            let added: Int?
            let removed: Int?
        }

        let database: Database?
        let ofcomCheck: OfcomCheck?
    }

    struct PhoneReport: Decodable {
        struct Day: Decodable {
            let blockedServer: Int
            let blockedPhone: Int
        }

        struct Prefix: Decodable {
            let prefix: String
            let blockedServer: Int
            let blockedPhone: Int
        }

        struct BlockedCall: Decodable {
            let time: Date
            let number: String
            let by: String
        }

        let generatedAt: Date
        let latestCallInHistory: Date?
        let daily: [Day]
        let byPrefix: [Prefix]
        let blockedCalls: [BlockedCall]

        var blockedLast7Days: Int { daily.suffix(7).reduce(0) { $0 + $1.blockedServer + $1.blockedPhone } }
        var blockedInReport: Int { daily.reduce(0) { $0 + $1.blockedServer + $1.blockedPhone } }
    }

    let server: Server
    let callsChecked: CallsChecked
    let errors7d: Int
    let mac: MacNotes?
    let phone: PhoneReport?

    /// Reads the server's snake_case keys. Foundation's own snake_case conversion turns
    /// "last_24h" into "last24H", so this one keeps a part that starts with a digit as it is.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .custom { path in
            let parts = path[path.count - 1].stringValue.split(separator: "_")
            let camel = parts.dropFirst().reduce(String(parts.first ?? "")) { $0 + $1.prefix(1).uppercased() + $1.dropFirst() }
            return Key(camel)
        }
        return decoder
    }()

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue _: Int) { nil }
    }
}

@MainActor
final class StatsModel: ObservableObject {
    enum State {
        case loading
        case loaded(ServerStats, answeredIn: Duration)
        case failed(String)
        case noServer
    }

    @Published private(set) var state = State.loading

    var stats: ServerStats? {
        if case let .loaded(stats, _) = state { return stats }
        return nil
    }

    func refresh() async {
#if FALLBACK_0843
        state = .noServer
#else
        guard !LookupSecrets.dashboardPassword.isEmpty else {
            state = .noServer
            return
        }
        var request = URLRequest(url: LookupSecrets.url.appendingPathComponent("dashboard/status.json"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let credentials = Data("app:\(LookupSecrets.dashboardPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let answeredIn = started.duration(to: clock.now)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                state = .failed("The server answered with error \(code).")
                return
            }
            state = .loaded(try ServerStats.decoder.decode(ServerStats.self, from: data), answeredIn: answeredIn)
        } catch {
            state = .failed(error.localizedDescription)
        }
#endif
    }
}

/// When this build's signing profile expires. A free Apple account signs for 7 days; after that
/// the app and its blocking parts stop working until scripts/resign.sh runs.
enum SigningProfile {
    static var expiry: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8))
        else { return nil }
        let plist = try? PropertyListSerialization.propertyList(
            from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }
}
