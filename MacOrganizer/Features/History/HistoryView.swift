import SwiftUI
import OrganizerCore

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: HistoryViewModel?
    @State private var detailRun: OperationRun?
    @State private var undoConfirmRun: OperationRun?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = HistoryViewModel(environment: environment) }
        }
        .task { await viewModel?.load() }
        .navigationTitle("History")
        .sheet(item: $detailRun) { run in
            RunDetailSheet(run: run)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await viewModel?.load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HistoryViewModel) -> some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.runs.isEmpty {
            EmptyStateView(symbolName: "clock", title: "No history yet", message: "Organize or clean up a folder and it will show up here.")
        } else {
            List {
                ForEach(viewModel.groupedByDay, id: \.day) { group in
                    Section(group.day) {
                        ForEach(group.runs) { run in
                            RunRow(run: run) {
                                detailRun = run
                            } undo: {
                                undoConfirmRun = run
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .confirmationDialog(
                "Undo this run?", isPresented: Binding(get: { undoConfirmRun != nil }, set: { if !$0 { undoConfirmRun = nil } }),
                titleVisibility: .visible
            ) {
                Button("Undo", role: .destructive) {
                    if let run = undoConfirmRun {
                        Task { await viewModel.undo(run) }
                    }
                    undoConfirmRun = nil
                }
                Button("Cancel", role: .cancel) { undoConfirmRun = nil }
            } message: {
                Text("Moves will be reversed where safe. Trashed items are not reversed here — use Finder's Put Back.")
            }
            if let result = viewModel.undoResult {
                UndoResultBanner(result: result) { viewModel.undoResult = nil }
            }
        }
    }
}

private struct RunRow: View {
    let run: OperationRun
    let showDetail: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(run.label).font(.body.weight(.medium))
                Text("\(run.startedAt.formatted(date: .omitted, time: .shortened)) · \(run.movedCount) moved · \(run.trashedCount) trashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if run.undoneAt != nil {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Undo", action: undo)
                    .buttonStyle(.bordered)
                    .disabled(run.movedCount == 0)
            }
            Button("View Details", action: showDetail)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }
}

private struct RunDetailSheet: View {
    let run: OperationRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(run.label).font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            List {
                if !run.errors.isEmpty {
                    Section("Errors") {
                        ForEach(run.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                }
                Section("Files (\(run.records.count))") {
                    ForEach(run.records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.source.lastPathComponent)
                            Text(record.kind == .trash ? "Trashed" : "Moved to \(record.destination?.abbreviatedPath ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 420)
    }
}

private struct UndoResultBanner: View {
    let result: UndoResult
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: result.outcomes.allSatisfy(\.isSuccess) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(result.outcomes.allSatisfy(\.isSuccess) ? .green : .orange)
            Text("Restored \(result.restoredCount) of \(result.outcomes.count) files.")
            if result.unreversedTrashedCount > 0 {
                Text("\(result.unreversedTrashedCount) trashed items need Finder's Put Back.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(.plain)
        }
        .font(.callout)
        .padding(12)
        .background(.regularMaterial)
    }
}
