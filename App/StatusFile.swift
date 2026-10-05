import Foundation

/// What the app last saw, saved as Documents/status.json so the Mac can read the phone's state
/// over the cable (scripts/phone_status.sh). Switch states and times only; never phone numbers.
struct StatusFile: Codable {
    struct Part: Codable {
        let name: String
        let on: Bool
    }

    /// The outcome of an action the user started, kept across app launches.
    struct Event: Codable {
        let at: Date
        let result: String
    }

    enum Action: String {
        case partsCheck, serverRefresh
    }

    let written: Date
    let version: String
    let summary: String
    let parts: [Part]
    let serverLookupOn: Bool?
    let lastPartsCheck: Event?
    let lastServerRefresh: Event?

    static func record(_ action: Action, _ result: String) {
        let event = Event(at: .now, result: result)
        UserDefaults.standard.set(try? JSONEncoder().encode(event), forKey: action.rawValue)
    }

    static func last(_ action: Action) -> Event? {
        guard let data = UserDefaults.standard.data(forKey: action.rawValue) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try encoder.encode(self).write(to: documents.appendingPathComponent("status.json"), options: .atomic)
    }
}
