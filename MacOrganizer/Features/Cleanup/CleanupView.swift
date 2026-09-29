import SwiftUI
import OrganizerCore

struct CleanupView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @State private var viewModel: CleanupViewModel?
    @State private var showTrashConfirmation = false

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
                viewModel = CleanupViewModel(environment: environment, root: settingsStore.settings.defaultFolder)
            }
        }
        .task { await viewModel?.loadIfNeeded() }
        .navigationTitle("Cleanup")
    }

    @ViewBuilder
    private func content(_ viewModel: CleanupViewModel) -> some View {
        if viewModel.isLoadingReport {
            ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.stage == .done {
            doneView(viewModel)
        } else {
            ZStack {
                VStack(spacing: 0) {
                    stageIndicator(viewModel)
                    Divider()
                    ScrollView {
                        stageContent(viewModel).padding(24)
                    }
                    Divider()
                    footer(viewModel)
                }
                .disabled(viewModel.isExecuting)

                if viewModel.isExecuting {
                    LoadingOverlay(
                        message: "Cleaning up…",
                        detail: "\(viewModel.totalTrashCount) trashing · \(viewModel.totalArchiveCount) archiving"
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isExecuting)
        }
    }

    private static let stageIcons: [CleanupStage: String] = [
        .duplicates: "doc.on.doc.fill", .installers: "shippingbox.fill",
        .oldFiles: "clock.arrow.circlepath", .emptyFolders: "folder", .review: "checkmark.seal.fill",
    ]

    private func stageIndicator(_ viewModel: CleanupViewModel) -> some View {
        HStack(spacing: 0) {
            ForEach(CleanupStage.allCases.filter { $0 != .done }) { stage in
                let isCurrent = stage == viewModel.stage
                let isPast = stage.rawValue < viewModel.stage.rawValue
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isPast ? Color.green : (isCurrent ? Color.accentColor : Color(.tertiaryLabelColor).opacity(0.3)))
                            .frame(width: 22, height: 22)
                        Image(systemName: isPast ? "checkmark" : Self.stageIcons[stage] ?? "circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(stage.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
                if stage != .review {
                    Rectangle()
                        .fill(isPast ? Color.green.opacity(0.5) : Color(.tertiaryLabelColor).opacity(0.25))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func stageContent(_ viewModel: CleanupViewModel) -> some View {
        switch viewModel.stage {
        case .duplicates: duplicatesStage(viewModel)
        case .installers: installersStage(viewModel)
        case .oldFiles: oldFilesStage(viewModel)
        case .emptyFolders: emptyFoldersStage(viewModel)
        case .review: reviewStage(viewModel)
        case .done: EmptyView()
        }
    }

    // MARK: Duplicates

    private func duplicatesStage(_ viewModel: CleanupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review each set. The suggested copy to keep is checked — never assume a duplicate should be deleted without looking.")
                .font(.callout).foregroundStyle(.secondary)

            if viewModel.duplicateGroups.isEmpty {
                EmptyStateView(symbolName: "doc.on.doc", title: "No duplicates", message: "Nothing to review here.")
            } else {
                ForEach(viewModel.duplicateGroups) { group in
                    let category = group.items.first.map { OrganizationRule.category(forFileNamed: $0.path.lastPathComponent, extension: $0.path.pathExtension) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: category?.symbolName ?? "doc.on.doc.fill")
                                .font(.caption)
                                .foregroundStyle(category.map(CategoryStyle.color) ?? .secondary)
                            Text("\(group.items.count) copies · \(group.sizeEachBytes.humanSize) each")
                                .font(.subheadline.weight(.semibold))
                        }
                        ForEach(group.items, id: \.path) { item in
                            let keepBinding = Binding<Bool>(
                                get: { viewModel.duplicateKeep[group.id]?.contains(item.path) ?? false },
                                set: { newValue in
                                    var keep = viewModel.duplicateKeep[group.id] ?? []
                                    if newValue { keep.insert(item.path) } else { keep.remove(item.path) }
                                    viewModel.duplicateKeep[group.id] = keep
                                }
                            )
                            Toggle(isOn: keepBinding) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    Text(item.path.abbreviatedPath).lineLimit(1)
                                    Spacer()
                                    Text(item.modificationDate.shortDate).font(.caption).foregroundStyle(.secondary)
                                    Button { FinderService.reveal([item.path]) } label: {
                                        Image(systemName: "arrow.forward.square")
                                    }.buttonStyle(.plain)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(12)
                    .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 8)
                }
            }
        }
    }

    // MARK: Installers

    private func installersStage(_ viewModel: CleanupViewModel) -> some View {
        selectableList(
            icon: "shippingbox.fill", tint: .brown,
            title: "Old installers — safe to remove once the app is installed.",
            items: viewModel.report?.oldInstallers ?? [],
            selection: Binding(get: { viewModel.selectedInstallers }, set: { viewModel.selectedInstallers = $0 }),
            emptyTitle: "No old installers", emptyMessage: "Nothing older than the threshold."
        )
    }

    // MARK: Old files

    private func oldFilesStage(_ viewModel: CleanupViewModel) -> some View {
        selectableList(
            icon: "clock.arrow.circlepath", tint: .orange,
            title: "Old files will be archived into _Archive/<year>/<type>/ — moved, not deleted, and can be undone from History.",
            items: viewModel.report?.oldFiles ?? [],
            selection: Binding(get: { viewModel.selectedOldFiles }, set: { viewModel.selectedOldFiles = $0 }),
            emptyTitle: "No old files", emptyMessage: "Nothing older than the threshold."
        )
    }

    private func selectableList(icon: String, tint: Color, title: String, items: [FileItem], selection: Binding<Set<URL>>, emptyTitle: String, emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.callout).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                EmptyStateView(symbolName: "checkmark.circle", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        let category = OrganizationRule.category(forFileNamed: item.path.lastPathComponent, extension: item.path.pathExtension)
                        Toggle(isOn: Binding(
                            get: { selection.wrappedValue.contains(item.path) },
                            set: { newValue in
                                if newValue { selection.wrappedValue.insert(item.path) } else { selection.wrappedValue.remove(item.path) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: category.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(CategoryStyle.color(for: category))
                                    .frame(width: 16)
                                Text(item.path.lastPathComponent).lineLimit(1)
                                Text(item.path.deletingLastPathComponent().abbreviatedPath)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(item.modificationDate.shortDate).font(.caption).foregroundStyle(.secondary)
                                Text(item.size.humanSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // MARK: Empty folders

    private func emptyFoldersStage(_ viewModel: CleanupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text("Recomputed after archiving — folders left empty by the previous step are included.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if viewModel.freshEmptyFolders.isEmpty {
                EmptyStateView(symbolName: "folder", title: "No empty folders", message: "Nothing to clean up here.")
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.freshEmptyFolders) { folder in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedEmptyFolders.contains(folder.path) },
                            set: { newValue in
                                if newValue { viewModel.selectedEmptyFolders.insert(folder.path) }
                                else { viewModel.selectedEmptyFolders.remove(folder.path) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(folder.path.abbreviatedPath)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // MARK: Review

    private func reviewStage(_ viewModel: CleanupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready to Move to Trash")
                .font(.title2.weight(.bold))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.totalTrashCount) files · \(viewModel.totalTrashBytes.humanSize)")
                        .font(.headline)
                    Text("Nothing will be permanently deleted. The selected files will be moved to the macOS Trash and can normally be restored using Finder's Put Back.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 10)

            if viewModel.totalArchiveCount > 0 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "archivebox.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(viewModel.totalArchiveCount) files · \(viewModel.totalArchiveBytes.humanSize) archived")
                            .font(.headline)
                        Text("Moved into _Archive/<year>/<type>/ — not trashed, and reversible from History.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 10)
            }
        }
    }

    // MARK: Footer

    private func footer(_ viewModel: CleanupViewModel) -> some View {
        HStack {
            if viewModel.stage != .duplicates {
                GlassActionButton(prominent: false, intensity: settingsStore.settings.glassIntensity) {
                    viewModel.back()
                } label: {
                    Text("Back")
                }
            }
            Spacer()
            if viewModel.stage == .review {
                GlassActionButton(prominent: true, intensity: settingsStore.settings.glassIntensity) {
                    showTrashConfirmation = true
                } label: {
                    Text("Move to Trash")
                }
                .disabled(viewModel.isExecuting)
                .confirmationDialog(
                    "Move \(viewModel.totalTrashCount) files to Trash and archive \(viewModel.totalArchiveCount) files?",
                    isPresented: $showTrashConfirmation, titleVisibility: .visible
                ) {
                    Button("Move to Trash", role: .destructive) { Task { await viewModel.execute() } }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                GlassActionButton(prominent: true, intensity: settingsStore.settings.glassIntensity) {
                    viewModel.advance()
                } label: {
                    Text("Next")
                }
            }
        }
        .padding(16)
    }

    private func doneView(_ viewModel: CleanupViewModel) -> some View {
        VStack(spacing: 14) {
            Image(systemName: viewModel.finalErrors.isEmpty ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(viewModel.finalErrors.isEmpty ? .green : .orange)
            Text("Cleanup complete")
                .font(.title2.weight(.semibold))
            Text("\(viewModel.finalRecordCounts.trashed) trashed · \(viewModel.finalRecordCounts.moved) archived")
                .foregroundStyle(.secondary)
            if !viewModel.finalErrors.isEmpty {
                DisclosureGroup("View Details") {
                    VStack(alignment: .leading) {
                        ForEach(viewModel.finalErrors, id: \.self) { Text($0).font(.caption) }
                    }
                }
                .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
