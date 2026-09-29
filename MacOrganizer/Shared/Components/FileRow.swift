import SwiftUI
import OrganizerCore

/// One file in a list: icon, name, size, date, with a Finder-reveal action.
/// Used across Report, Cleanup and History detail lists.
struct FileRow: View {
    let url: URL
    let size: Int64
    let modificationDate: Date?
    var caption: String?
    var symbolName: String = "doc"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(url.deletingLastPathComponent().abbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 12)
            if let modificationDate {
                Text(modificationDate.shortDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            Text(size.humanSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Button {
                FinderService.reveal([url])
            } label: {
                Image(systemName: "arrow.forward.square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
        }
        .contextMenu {
            Button("Reveal in Finder") { FinderService.reveal([url]) }
        }
        .padding(.vertical, 2)
    }
}
