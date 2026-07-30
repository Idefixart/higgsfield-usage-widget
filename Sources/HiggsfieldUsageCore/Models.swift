import Foundation

// MARK: - ISO8601 parsing

public enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ISO8601DateFormatter only accepts exactly 3 fractional digits; the API
    /// sends 6. Truncate/pad the fraction to 3 digits before parsing.
    static func normalizeFraction(_ s: String) -> String {
        guard let r = s.range(of: #"\.\d+"#, options: .regularExpression) else { return s }
        var digits = String(s[r].dropFirst())
        if digits.count > 3 { digits = String(digits.prefix(3)) }
        while digits.count < 3 { digits += "0" }
        return s.replacingCharacters(in: r, with: "." + digits)
    }

    public static func parse(_ s: String) -> Date? {
        fractional.date(from: normalizeFraction(s)) ?? plain.date(from: s)
    }
}

// MARK: - API models

public struct AccountStatus: Codable, Equatable {
    public let email: String
    public let credits: Double
    public let subscriptionPlanType: String

    enum CodingKeys: String, CodingKey {
        case email, credits
        case subscriptionPlanType = "subscription_plan_type"
    }

    public init(email: String, credits: Double, subscriptionPlanType: String) {
        self.email = email
        self.credits = credits
        self.subscriptionPlanType = subscriptionPlanType
    }
}

public struct Transaction: Codable, Equatable, Hashable {
    public let displayName: String
    public let credits: Double
    public let action: String
    /// Raw ISO8601 string, kept verbatim so the dedupe key survives
    /// encode/decode cycles without losing microsecond precision.
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case credits, action
        case displayName = "display_name"
        case createdAt = "created_at"
    }

    public init(displayName: String, credits: Double, action: String, createdAt: String) {
        self.displayName = displayName
        self.credits = credits
        self.action = action
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "—"
        credits = try c.decodeIfPresent(Double.self, forKey: .credits) ?? 0
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    public var date: Date? { ISO8601.parse(createdAt) }
    public var dedupeKey: String { "\(createdAt)|\(displayName)|\(credits)" }
}

public enum APIDecode {
    public static func status(from data: Data) throws -> AccountStatus {
        try JSONDecoder().decode(AccountStatus.self, from: data)
    }
    public static func transactions(from data: Data) throws -> [Transaction] {
        try JSONDecoder().decode([Transaction].self, from: data)
    }
}
