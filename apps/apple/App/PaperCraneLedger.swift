import Foundation

struct PaperCraneLedger {
    struct Credit: Codable, Equatable {
        let run: UUID
        let cranes: Int
    }

    private struct Stored: Codable {
        let total: Int
        let credits: [Credit]
    }

    static let storageKey = "littlewhile.cranes.v1"
    static let remembered = 16

    private let defaults: UserDefaults
    private(set) var total: Int
    private(set) var credits: [Credit]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        total = max(0, stored?.total ?? 0)
        credits = stored?.credits ?? []
    }

    func credited(_ run: UUID) -> Int {
        credits.last { $0.run == run }?.cranes ?? 0
    }

    func count(run: UUID, cranes: Int) -> Int {
        total + max(0, cranes - credited(run))
    }

    mutating func credit(run: UUID, cranes: Int) {
        let gained = cranes - credited(run)
        guard gained > 0 else { return }
        total += gained
        credits.removeAll { $0.run == run }
        credits.append(Credit(run: run, cranes: cranes))
        credits = Array(credits.suffix(Self.remembered))
        guard let data = try? JSONEncoder().encode(Stored(total: total, credits: credits)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
