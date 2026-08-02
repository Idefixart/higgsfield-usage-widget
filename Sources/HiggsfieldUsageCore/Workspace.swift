import Foundation

/// A billing workspace as `higgsfield workspace list --json` reports it.
/// Credits are charged against the selected one, so an account with several
/// workspaces has to pick before `account status` answers at all.
public struct Workspace: Codable, Equatable, Identifiable {
    public let id: String
    /// Null for a personal workspace, which the CLI leaves unnamed.
    public let name: String?
    public let planType: String
    public let credits: Double
    public let isSelected: Bool
    public let userRole: String

    enum CodingKeys: String, CodingKey {
        case id, name, credits
        case planType = "plan_type"
        case isSelected = "is_selected"
        case userRole = "user_role"
    }

    public init(id: String, name: String?, planType: String, credits: Double,
                isSelected: Bool, userRole: String) {
        self.id = id
        self.name = name
        self.planType = planType
        self.credits = credits
        self.isSelected = isSelected
        self.userRole = userRole
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        planType = try c.decodeIfPresent(String.self, forKey: .planType) ?? ""
        credits = try c.decodeIfPresent(Double.self, forKey: .credits) ?? 0
        isSelected = try c.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        userRole = try c.decodeIfPresent(String.self, forKey: .userRole) ?? ""
    }

    /// Unnamed workspaces still have to be told apart in a list, so fall back
    /// to the plan and finally to a short id rather than rendering a blank row.
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if !planType.isEmpty { return planType.capitalized }
        return String(id.prefix(8))
    }
}

/// Classifies the CLI's "no workspace selected" refusal, which arrives as plain
/// stderr text with no machine-readable code — the same shape as [AuthState].
public enum WorkspaceState {
    static let markers = [
        "no workspace selected",
        "workspace set <workspace_id>",
    ]

    public static func isMissingSelection(_ message: String) -> Bool {
        let lower = message.lowercased()
        return markers.contains { lower.contains($0) }
    }

    public static func list(from data: Data) throws -> [Workspace] {
        try JSONDecoder().decode([Workspace].self, from: data)
    }
}
