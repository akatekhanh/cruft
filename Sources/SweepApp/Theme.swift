import SwiftUI
import SweepCore

/// Visual theme constants shared across all views.
enum Theme {
    /// Friendly, calm teal accent — never alarming.
    static let accent = Color(red: 0.06, green: 0.65, blue: 0.63)

    /// Maps a risk level to its semantic color. Used only for small dots/badges,
    /// never as a full-row fill, per DESIGN.md section 5.
    static func color(for risk: RiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .risky: return .red
        }
    }
}

/// Small dot + plain-language label describing a risk level.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.color(for: risk))
                .frame(width: 8, height: 8)
            Text(risk.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
