import SwiftUI
import OrganizerCore

/// Shared color coding for FileCategory, used by Organize's preview list and
/// Report's category chart so the same category always reads the same color.
enum CategoryStyle {
    static let colors: [FileCategory: Color] = [
        .images: .blue, .videos: .purple, .audio: .pink, .documents: .orange,
        .spreadsheets: .green, .presentations: .red, .archives: .brown,
        .installers: .gray, .code: .indigo, .fonts: .teal, .screenshots: .cyan, .other: .secondary,
    ]

    static func color(for category: FileCategory) -> Color {
        colors[category] ?? .secondary
    }
}
