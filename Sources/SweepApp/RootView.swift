import SwiftUI

/// Switches between screens based on `AppModel.phase`, with a gentle crossfade.
struct RootView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if showsRoleTabs {
                RoleTabBar(model: model)
                Divider()
            }
            if model.selectedTab == "overview", showsRoleTabs {
                OverviewView(model: model)
            } else {
                content
            }
        }
    }

    /// Onboarding picks the first role itself; Done is a moment of calm — no tabs.
    private var showsRoleTabs: Bool {
        switch model.phase {
        case .idle, .scanning, .results: return true
        case .onboarding, .done: return false
        }
    }

    private var content: some View {
        Group {
            switch model.phase {
            case .onboarding:
                OnboardingView(model: model)
                    .transition(.opacity)
            case .idle:
                DashboardView(model: model)
                    .transition(.opacity)
            case .scanning(let progress):
                ScanningView(model: model, progress: progress)
                    .transition(.opacity)
            case .results:
                ResultsView(model: model)
                    .transition(.opacity)
            case .done(let report):
                DoneView(model: model, report: report)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phaseTag)
    }

    /// Simple tag so `.animation(value:)` can compare phases without Equatable.
    private var phaseTag: Int {
        switch model.phase {
        case .onboarding: return 0
        case .idle: return 1
        case .scanning: return 2
        case .results: return 3
        case .done: return 4
        }
    }
}
