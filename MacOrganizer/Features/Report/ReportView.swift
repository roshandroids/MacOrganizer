import SwiftUI
import Charts
import OrganizerCore

private struct CategoryStat: Identifiable {
    let category: FileCategory
    let count: Int
    let bytes: Int64
    var id: String { category.rawValue }
}

struct ReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @State private var categoryStats: [CategoryStat] = []

    private var root: URL { settingsStore.settings.defaultFolder }
    private var coordinator: ScanCoordinator { environment.scanCoordinator }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch coordinator.state {
                case .idle:
                    ProgressView().onAppear { coordinator.refresh(root: root) }
                case .scanning(let count):
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Scanning… \(count) files")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    EmptyStateView(symbolName: "exclamationmark.triangle", title: "Couldn't build report", message: message)
                case .loaded:
                    if let report = coordinator.report {
                        headline(report)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                categoryDonut(report).frame(maxWidth: .infinity)
                                opportunityCallout(report).frame(maxWidth: .infinity)
                            }
                            VStack(alignment: .leading, spacing: 20) {
                                categoryDonut(report)
                                opportunityCallout(report)
                            }
                        }
                        detailSections(report)
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Report")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { coordinator.refresh(root: root, force: true) } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
        }
        .task(id: coordinator.report?.scannedAt) {
            guard let report = coordinator.report else { return }
            categoryStats = Self.computeCategoryStats(report)
        }
    }

    private static func computeCategoryStats(_ report: ScanReport) -> [CategoryStat] {
        var counts: [FileCategory: (Int, Int64)] = [:]
        for file in report.files {
            let category = OrganizationRule.category(forFileNamed: file.path.lastPathComponent, extension: file.path.pathExtension)
            var entry = counts[category] ?? (0, 0)
            entry.0 += 1
            entry.1 += file.size
            counts[category] = entry
        }
        return counts
            .map { CategoryStat(category: $0.key, count: $0.value.0, bytes: $0.value.1) }
            .sorted { $0.bytes > $1.bytes }
    }

    // MARK: Headline numbers

    private func headline(_ report: ScanReport) -> some View {
        let policy = PathPolicy.system()
        let extras = DuplicateSelection.extras(groups: report.duplicateGroups, keepDirectories: settingsStore.resolvedKeepDirectories, policy: policy)
        let reclaimable = extras.reduce(Int64(0)) { $0 + $1.size } + report.oldInstallers.reduce(Int64(0)) { $0 + $1.size }

        return VStack(alignment: .leading, spacing: 6) {
            Text(root.lastPathComponent).font(.largeTitle.weight(.bold))
            HStack(spacing: 28) {
                StatTile(title: "Files", value: "\(report.files.count)", symbolName: "doc.on.doc")
                StatTile(title: "Total size", value: report.totalBytes.humanSize, symbolName: "internaldrive")
                if reclaimable > 0 {
                    StatTile(title: "Could reclaim", value: reclaimable.humanSize, tint: .orange, symbolName: "sparkles")
                }
            }
        }
    }

    // MARK: Category donut — the one chart that matters: "what's taking up space"

    private func categoryDonut(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's taking up space").font(.title3.weight(.semibold))
            if categoryStats.isEmpty {
                Text("No files yet.").foregroundStyle(.secondary)
            } else {
                Chart(categoryStats.prefix(8)) { stat in
                    SectorMark(angle: .value("Size", stat.bytes), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(CategoryStyle.color(for: stat.category))
                        .cornerRadius(3)
                }
                .frame(height: 200)
                .chartLegend(.hidden)
                .overlay {
                    if let biggest = categoryStats.first {
                        VStack(spacing: 2) {
                            Text(biggest.category.rawValue).font(.caption.weight(.semibold))
                            Text(biggest.bytes.humanSize).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(categoryStats.prefix(6)) { stat in
                        HStack(spacing: 8) {
                            Circle().fill(CategoryStyle.color(for: stat.category)).frame(width: 8, height: 8)
                            Text(stat.category.rawValue).font(.caption)
                            Spacer()
                            Text("\(stat.count)").font(.caption).foregroundStyle(.secondary)
                            Text(stat.bytes.humanSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 12)
    }

    // MARK: Opportunity callout — the plain-English "so what"

    private func opportunityCallout(_ report: ScanReport) -> some View {
        let policy = PathPolicy.system()
        let extrasCount = DuplicateSelection.extras(groups: report.duplicateGroups, keepDirectories: settingsStore.resolvedKeepDirectories, policy: policy).count

        return VStack(alignment: .leading, spacing: 12) {
            Text("At a glance").font(.title3.weight(.semibold))
            glanceRow(icon: "doc.on.doc.fill", tint: .blue, text: extrasCount == 0 ? "No duplicate files" : "\(extrasCount) duplicate file\(extrasCount == 1 ? "" : "s") found")
            glanceRow(icon: "clock.arrow.circlepath", tint: .orange, text: report.oldFiles.isEmpty ? "Nothing old enough to archive" : "\(report.oldFiles.count) file\(report.oldFiles.count == 1 ? "" : "s") haven't been touched in a while")
            glanceRow(icon: "shippingbox.fill", tint: .brown, text: report.oldInstallers.isEmpty ? "No stale installers" : "\(report.oldInstallers.count) installer\(report.oldInstallers.count == 1 ? "" : "s") likely already used")
            glanceRow(icon: "folder", tint: .gray, text: report.emptyFolders.isEmpty ? "No empty folders" : "\(report.emptyFolders.count) empty folder\(report.emptyFolders.count == 1 ? "" : "s")")
            if !report.largeFiles.isEmpty {
                glanceRow(icon: "arrow.up.circle.fill", tint: .red, text: "Biggest file: \(report.largeFiles[0].path.lastPathComponent) (\(report.largeFiles[0].size.humanSize))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(intensity: settingsStore.settings.glassIntensity, cornerRadius: 12)
    }

    private func glanceRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
            Text(text).font(.callout)
            Spacer()
        }
    }

    // MARK: Details — collapsed by default so the page isn't a wall of files

    private func detailSections(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            detailGroup(title: "Largest files (\(report.largeFiles.count))", isEmpty: report.largeFiles.isEmpty) {
                fileList(report.largeFiles)
            }
            detailGroup(title: "Duplicate sets (\(report.duplicateGroups.count))", isEmpty: report.duplicateGroups.isEmpty) {
                duplicateList(report)
            }
            detailGroup(title: "Old files (\(report.oldFiles.count))", isEmpty: report.oldFiles.isEmpty) {
                fileList(report.oldFiles)
            }
            detailGroup(title: "Old installers (\(report.oldInstallers.count))", isEmpty: report.oldInstallers.isEmpty) {
                fileList(report.oldInstallers)
            }
            detailGroup(title: "Empty folders (\(report.emptyFolders.count))", isEmpty: report.emptyFolders.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.emptyFolders) { folder in
                        Text(folder.path.abbreviatedPath).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailGroup<Content: View>(title: String, isEmpty: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        if !isEmpty {
            DisclosureGroup(title) {
                content().padding(.top, 6)
            }
            .padding(.vertical, 6)
            Divider()
        }
    }

    private func fileList(_ files: [FileItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(files.prefix(15)) { file in
                let category = OrganizationRule.category(forFileNamed: file.path.lastPathComponent, extension: file.path.pathExtension)
                FileRow(url: file.path, size: file.size, modificationDate: file.modificationDate, symbolName: category.symbolName)
                if file.id != files.prefix(15).last?.id { Divider() }
            }
        }
    }

    private func duplicateList(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(report.duplicateGroups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }.prefix(10)) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.items.count) copies · \(group.sizeEachBytes.humanSize) each")
                        .font(.subheadline.weight(.medium))
                    ForEach(group.items, id: \.path) { item in
                        Text(item.path.abbreviatedPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}
