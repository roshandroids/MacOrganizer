import SwiftUI
import OrganizerCore

struct OrganizeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @State private var viewModel: OrganizeViewModel?
    @State private var showApplyConfirmation = false

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
                viewModel = OrganizeViewModel(
                    environment: environment, initialRoot: settingsStore.settings.defaultFolder,
                    byDate: settingsStore.settings.organizeByDate
                )
            }
        }
        .navigationTitle("Organize")
    }

    @ViewBuilder
    private func content(_ viewModel: OrganizeViewModel) -> some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    configuration(viewModel)

                    if let error = viewModel.protectedPathError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    switch viewModel.phase {
                    case .configuring:
                        EmptyView()
                    case .previewed, .applying:
                        if let plan = viewModel.plan {
                            previewSection(viewModel, plan: plan)
                        }
                    case .done(let moved, let skipped, let errorCount):
                        resultSection(viewModel, moved: moved, skipped: skipped, errorCount: errorCount)
                    }
                }
                .padding(28)
            }
            .disabled(viewModel.phase == .applying)

            if viewModel.phase == .applying {
                LoadingOverlay(
                    message: "Organizing files…",
                    detail: "\(viewModel.plan?.moves.count ?? 0) files moving into place"
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.phase == .applying)
        .confirmationDialog(
            "Apply these moves now?",
            isPresented: $showApplyConfirmation, titleVisibility: .visible
        ) {
            Button("Apply \(viewModel.plan?.moves.count ?? 0) moves") {
                Task { await viewModel.apply() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files will be moved into type folders inside \(viewModel.root.abbreviatedPath). This can be undone from History.")
        }
    }

    private func configuration(_ viewModel: OrganizeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder").font(.subheadline).foregroundStyle(.secondary)
                    Text(viewModel.root.abbreviatedPath)
                }
                Spacer()
                Button("Choose…") { viewModel.chooseFolder() }
            }

            Toggle("Organize by date (YYYY-MM subfolders)", isOn: Binding(
                get: { viewModel.byDate },
                set: { viewModel.byDate = $0 }
            ))

            HStack {
                GlassActionButton(prominent: false, intensity: settingsStore.settings.glassIntensity) {
                    Task { await viewModel.preview() }
                } label: {
                    Label("Preview", systemImage: "eye")
                }

                if viewModel.phase == .previewed || { if case .done = viewModel.phase { return true }; return false }() {
                    Button("Start Over") { viewModel.reset() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 10)
    }

    private func previewSection(_ viewModel: OrganizeViewModel, plan: OrganizePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if plan.moves.isEmpty {
                EmptyStateView(
                    symbolName: "checkmark.circle", title: "Nothing to organize",
                    message: "No top-level files are eligible to move right now."
                )
            } else {
                HStack {
                    Text("\(plan.moves.count) file\(plan.moves.count == 1 ? "" : "s") will move")
                        .font(.headline)
                    if plan.skippedCount > 0 {
                        Text("· \(plan.skippedCount) skipped (in progress / too new)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassActionButton(prominent: true, intensity: settingsStore.settings.glassIntensity) {
                        showApplyConfirmation = true
                    } label: {
                        Label("Apply", systemImage: "checkmark")
                    }
                    .disabled(viewModel.phase == .applying)
                }

                ForEach(viewModel.groupedByDestination, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        let category = group.moves.first?.category
                        HStack(spacing: 6) {
                            Image(systemName: category?.symbolName ?? "folder")
                                .font(.caption)
                                .foregroundStyle(category.map(CategoryStyle.color) ?? .secondary)
                            Text(group.category).font(.subheadline.weight(.semibold))
                            Text("\(group.moves.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((category.map(CategoryStyle.color) ?? .secondary).opacity(0.12), in: Capsule())

                        VStack(spacing: 0) {
                            ForEach(group.moves) { move in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(move.source.path.lastPathComponent)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption2)
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(move.destination.deletingLastPathComponent().path.replacingOccurrences(of: viewModel.root.path + "/", with: "") + "/")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .font(.callout)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func resultSection(_ viewModel: OrganizeViewModel, moved: Int, skipped: Int, errorCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                errorCount == 0 ? "\(moved) files organized" : "\(moved) files organized, \(errorCount) skipped",
                systemImage: errorCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(errorCount == 0 ? .green : .orange)

            if !viewModel.applyErrors.isEmpty {
                DisclosureGroup("View Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.applyErrors, id: \.self) { message in
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("Organize Again") { viewModel.reset() }
        }
    }
}
