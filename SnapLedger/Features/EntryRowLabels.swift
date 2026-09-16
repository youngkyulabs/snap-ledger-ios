import SwiftUI

/// Category capsule shown on review and history rows.
struct CategoryChip: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(.secondarySystemFill), in: .capsule)
    }
}

/// Single-line note preview marked with a memo glyph so it reads apart from the category.
struct NotePreview: View {
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "text.bubble")
                .font(.caption2)
            Text(note)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("메모, \(note)")
    }
}
