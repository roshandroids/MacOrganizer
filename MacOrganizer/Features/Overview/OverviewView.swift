import SwiftUI
import OrganizerCore

struct OverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @State private var viewModel: OverviewViewModel?
    var navigate: (NavigationDestination) -> Void

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = OverviewViewModel(environment: environment)
                Task { await viewModel?.refreshAll() }
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel?.refreshAll() }
                } label: {
                    Label("Rescan All", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: OverviewViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Mac").font(.largeTitle.weight(.bold))
                    Text("Tap a folder to see what it needs.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 18)], spacing: 18) {
                    ForEach(viewModel.cards) { card in
                        FolderCardView(card: card, glassIntensity: settingsStore.settings.glassIntensity) { destination in
                            settingsStore.setWorkingFolder(card.url)
                            environment.scanCoordinator.refresh(root: card.url, force: true)
                            navigate(destination)
                        } grantAccess: {
                            viewModel.grantAccess(for: card)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct FolderCardView: View {
    let card: FolderCard
    let glassIntensity: Double
    let navigate: (NavigationDestination) -> Void
    let grantAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon badge + name + path
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconTint.gradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: card.symbolName)
                        .foregroundStyle(.white)
                        .font(.system(size: 19, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.displayName).font(.headline)
                    Text(card.url.abbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                statusDot
            }
            .padding(16)

            Divider()

            // Body: stats + suggestion + actions, fixed-height so cards align in the grid
            VStack(alignment: .leading, spacing: 14) {
                statsAndSuggestion
                actionRow
            }
            .padding(16)
            .frame(minHeight: 108, alignment: .top)
        }
        .glassPanel(intensity: glassIntensity, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(card.needsAttention ? Color.orange.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusDot: some View {
        switch card.state {
        case .loaded where card.needsAttention:
            Circle().fill(Color.orange).frame(width: 8, height: 8)
        case .loaded:
            Circle().fill(Color.green).frame(width: 8, height: 8)
        case .needsAccess:
            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
        case .loading:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statsAndSuggestion: some View {
        switch card.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning…").font(.callout).foregroundStyle(.secondary)
            }

        case .needsAccess:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("Grant access to see what's inside.")
                    .font(.callout).foregroundStyle(.secondary)
            }

        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

        case .loaded:
            HStack(spacing: 24) {
                statPair(icon: "doc.fill", value: "\(card.fileCount)", label: "files")
                statPair(icon: "opticaldiscdrive", value: card.totalBytes.humanSize, label: "size")
            }
            HStack(spacing: 6) {
                Image(systemName: card.needsAttention ? "wand.and.stars" : "checkmark.circle.fill")
                    .foregroundStyle(card.needsAttention ? .orange : .green)
                    .font(.caption)
                Text(card.suggestion)
                    .font(.callout)
                    .foregroundStyle(card.needsAttention ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((card.needsAttention ? Color.orange : Color.green).opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if case .needsAccess = card.state {
            GlassActionButton(prominent: false, intensity: glassIntensity, action: grantAccess) {
                Text("Allow Access…")
            }
        } else if case .loaded = card.state {
            HStack(spacing: 8) {
                GlassActionButton(prominent: true, intensity: glassIntensity) {
                    navigate(.organize)
                } label: {
                    Label("Organize", systemImage: "folder.badge.gearshape")
                }
                .controlSize(.small)
                .disabled(card.organizableCount == 0)

                GlassActionButton(prominent: false, intensity: glassIntensity) {
                    navigate(.cleanup)
                } label: {
                    Label("Cleanup", systemImage: "sparkles")
                }
                .controlSize(.small)

                GlassActionButton(prominent: false, intensity: glassIntensity) {
                    navigate(.report)
                } label: {
                    Label("Report", systemImage: "chart.pie")
                }
                .controlSize(.small)
                Spacer()
            }
            .labelStyle(.titleOnly)
        }
    }

    private var iconTint: Color {
        switch card.id {
        case "desktop": return .blue
        case "documents": return .indigo
        case "downloads": return .teal
        default: return .purple
        }
    }

    private func statPair(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
