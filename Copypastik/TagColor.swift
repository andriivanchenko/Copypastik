import SwiftUI

enum TagColor: String, CaseIterable, Identifiable, Codable {
    case sky
    case mint
    case lilac
    case rose
    case peach
    case lemon
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sky:
            return "Sky"
        case .mint:
            return "Mint"
        case .lilac:
            return "Lilac"
        case .rose:
            return "Rose"
        case .peach:
            return "Peach"
        case .lemon:
            return "Lemon"
        case .graphite:
            return "Graphite"
        }
    }

    static func automatic(for tag: String) -> TagColor {
        let colors = Array(allCases)
        let value = tag.unicodeScalars.reduce(into: UInt32(2166136261)) { hash, scalar in
            hash ^= scalar.value
            hash &*= 16777619
        }
        return colors[Int(value % UInt32(colors.count))]
    }

    var base: Color {
        switch self {
        case .sky:
            return Color(red: 0.36, green: 0.65, blue: 1.00)
        case .mint:
            return Color(red: 0.34, green: 0.76, blue: 0.60)
        case .lilac:
            return Color(red: 0.66, green: 0.57, blue: 0.94)
        case .rose:
            return Color(red: 0.93, green: 0.47, blue: 0.62)
        case .peach:
            return Color(red: 0.96, green: 0.62, blue: 0.39)
        case .lemon:
            return Color(red: 0.86, green: 0.70, blue: 0.25)
        case .graphite:
            return Color(red: 0.52, green: 0.58, blue: 0.66)
        }
    }

    var foreground: Color {
        switch self {
        case .sky:
            return Color(red: 0.05, green: 0.33, blue: 0.72)
        case .mint:
            return Color(red: 0.08, green: 0.42, blue: 0.28)
        case .lilac:
            return Color(red: 0.32, green: 0.23, blue: 0.66)
        case .rose:
            return Color(red: 0.62, green: 0.15, blue: 0.30)
        case .peach:
            return Color(red: 0.60, green: 0.28, blue: 0.08)
        case .lemon:
            return Color(red: 0.48, green: 0.36, blue: 0.06)
        case .graphite:
            return Color(red: 0.26, green: 0.31, blue: 0.38)
        }
    }
}
