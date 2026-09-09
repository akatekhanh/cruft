import SwiftUI
import SweepCore

/// Post-scan review screen: NavigationSplitView with a category sidebar and a
/// risk-grouped detail list, plus a footer bar to commit the clean.
struct ResultsView: View {
    var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarList(model: model)
        } detail: {
            DetailList(model: model)
                .safeAreaInset(edge: .top) {
                    if !model.quickCleanItems.isEmpty {
                        QuickCleanBanner(model: model)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    FooterBar(model: model)
                }
        }
    }
}

// MARK: - Sidebar

private struct SidebarList: View {
    var model: AppModel

    private var totalBytes: Int64 {
        model.results.reduce(0) { $0 + $1.totalBytes }
    }

    var body: some View {
        List(selection: Binding(
            get: { model.selectedCategoryID },
            set: { model.selectedCategoryID = $0 }
        )) {
            HStack {
                Label("All results", systemImage: "square.stack")
                Spacer()
                Text(ByteText.string(totalBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .tag(String?.none)

            ForEach(model.results) { result in
                HStack {
                    Image(systemName: result.category.systemImage)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    Text(result.category.name)
                    Circle()
                        .fill(Theme.color(for: result.category.risk))
                        .frame(width: 8, height: 8)
                    Spacer()
                    Text(ByteText.string(result.totalBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(String?.some(result.category.id))
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}

// MARK: - Detail

private struct DetailList: View {
    var model: AppModel

    private var visibleResults: [CategoryScanResult] {
        guard let id = model.selectedCategoryID else { return model.results }
        return model.results.filter { $0.category.id == id }
    }

    private func categoryFor(_ item: ScanItem) -> CleanCategory? {
        model.results.first { $0.category.id == item.categoryID }?.category
    }

    private func items(risk: RiskLevel) -> [ScanItem] {
        visibleResults.flatMap(\.items).filter { $0.risk == risk }
    }

    var body: some View {
        List {
            riskSection(.safe)
            riskSection(.review)
            riskySection
        }
        .listStyle(.inset)
        .navigationTitle(model.selectedCategoryID.flatMap { id in
            model.results.first { $0.category.id == id }?.category.name
        } ?? "All results")
    }

    @ViewBuilder
    private func riskSection(_ risk: RiskLevel) -> some View {
        let rows = items(risk: risk)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { item in
                    ItemRow(model: model, item: item, category: categoryFor(item))
                }
            } header: {
                RiskBadge(risk: risk)
            }
        }
    }

    @ViewBuilder
    private var riskySection: some View {
        let rows = items(risk: .risky)
        if !rows.isEmpty {
            let bytes = rows.reduce(0) { $0 + $1.sizeBytes }
            Section {
                DisclosureGroup("Show risky items (\(rows.count) items, \(ByteText.string(bytes)))") {
                    ForEach(rows) { item in
                        ItemRow(model: model, item: item, category: categoryFor(item))
                    }
                }
            } header: {
                RiskBadge(risk: .risky)
            }
        }
    }
}

private struct ItemRow: View {
    var model: AppModel
    let item: ScanItem
    let category: CleanCategory?

    private var isSelected: Bool { model.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.toggle(item: item)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            if let category {
                Image(systemName: category.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let category {
                    Text(category.consequence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(ByteText.string(item.sizeBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.toggle(item: item)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick clean (Smart Clean tab)

/// One honest button: cleans every Safe, Trash-recoverable item found anywhere.
/// Docker/permanent items never join a single click — they stay opt-in below.
private struct QuickCleanBanner: View {
    var model: AppModel

    var body: some View {
        let items = model.quickCleanItems
        let bytes = items.reduce(0) { $0 + $1.sizeBytes }
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick clean: \(items.count) items · \(ByteText.string(bytes))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("All Safe — everything goes to the Trash and can be restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quick clean") {
                model.quickClean()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(model.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    var model: AppModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected: \(ByteText.string(model.selectedBytes)) · \(model.selectedCount) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if model.selectionHasExternalRemoval {
                    Text("Docker items are removed by Docker itself — they do not go to the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Rescan") {
                model.rescan()
            }
            .buttonStyle(.bordered)
            .disabled(model.isCleaning)

            Button {
                model.clean()
            } label: {
                if model.isCleaning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else if model.selectionHasExternalRemoval {
                    Text("Clean \(ByteText.string(model.selectedBytes))")
                } else {
                    Text("Move \(ByteText.string(model.selectedBytes)) to Trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(model.selection.isEmpty || model.isCleaning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}
