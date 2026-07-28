import Foundation

// Written by the main app after every fetch, read by the WidgetKit extension
// through the shared App Group container.

public let appGroupID = "group.com.higgsfield.usage-widget"

public struct CreditsSnapshot: Codable {
    public struct Model: Codable {
        public var name: String
        public var credits: Double
        public var generations: Int
        public init(name: String, credits: Double, generations: Int) {
            self.name = name
            self.credits = credits
            self.generations = generations
        }
    }

    public var credits: Double
    public var plan: String
    public var topModels: [Model]
    public var windowLabel: String
    public var warnBelow: Double
    public var updatedAt: Date
    public var error: String?

    public init(credits: Double, plan: String, topModels: [Model], windowLabel: String,
                warnBelow: Double, updatedAt: Date, error: String?) {
        self.credits = credits
        self.plan = plan
        self.topModels = topModels
        self.windowLabel = windowLabel
        self.warnBelow = warnBelow
        self.updatedAt = updatedAt
        self.error = error
    }

    public static let placeholder = CreditsSnapshot(
        credits: 2451, plan: "creator",
        topModels: [
            Model(name: "Nano Banana Pro", credits: 486, generations: 243),
            Model(name: "Seedance 2.0", credits: 240, generations: 12),
            Model(name: "Kling 3.0", credits: 180, generations: 9),
        ],
        windowLabel: "7d", warnBelow: 500, updatedAt: Date(), error: nil)
}

public enum SharedStore {
    /// `containerURL(...)` works when the calling binary carries the app-group
    /// entitlement (the sandboxed widget); the non-sandboxed main app falls
    /// back to the literal path, which is the same folder.
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroupID)", isDirectory: true)
    }

    public static var snapshotURL: URL { containerURL.appendingPathComponent("credits-snapshot.json") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func write(_ snapshot: CreditsSnapshot) {
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    public static func read() -> CreditsSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(CreditsSnapshot.self, from: data)
    }
}
