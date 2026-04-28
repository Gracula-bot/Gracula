public enum ToolRiskLevel: String, Codable, Sendable, Equatable, Comparable, CaseIterable {
    case safe
    case reversible
    case externalCommunication
    case financialOrCritical

    public static func < (lhs: ToolRiskLevel, rhs: ToolRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .safe:
            0
        case .reversible:
            1
        case .externalCommunication:
            2
        case .financialOrCritical:
            3
        }
    }
}

