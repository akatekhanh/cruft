import SwiftUI
import CruftCore

/// Top tab bar: Overview (machine status), then Smart Clean and every role —
/// the quick way to sweep the whole machine role by role. In the results screen
/// a role-tab switch scans the new role immediately; on the dashboard it just
/// selects (Scan stays the explicit step).
struct RoleTabBar: View {
    var model: AppModel

    private var isScanning: Bool {
        if case .scanning = model.phase { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 4) {
            tab(id: "overview", name: "Overview",
                systemImage: "gauge.with.dots.needle.50percent",
                help: "How full this Mac is right now.")
            Divider().frame(height: 18)
            ForEach(Catalog.tabRoles) { role in
                tab(id: role.id, name: role.name,
                    systemImage: role.systemImage, help: role.blurb)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func tab(id: String, name: String, systemImage: String,
                     help: String) -> some View {
        let selected = id == model.selectedTab
        return Button {
            model.selectTab(id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(name)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? Theme.accent.opacity(0.15) : .clear))
            .foregroundStyle(selected ? Theme.accent : .secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isScanning && id != "overview")
        .help(help)
        .accessibilityLabel("\(name) tab")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
