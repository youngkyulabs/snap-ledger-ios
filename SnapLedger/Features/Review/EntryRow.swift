import SwiftUI
import SwiftData

struct EntryRow: View {
    let entry: ParsedEntry

    private var category: String? {
        guard let category = entry.category, !category.isEmpty else { return nil }
        return category
    }

    private var note: String? {
        guard let note = entry.note, !note.isEmpty else { return nil }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.merchant)
                    .font(.body)
                Spacer()
                Text("\(entry.amount.formatted(.number))원")
                    .font(.body.monospacedDigit())
            }
            if category != nil || note != nil {
                HStack(spacing: 6) {
                    if let category {
                        CategoryChip(category: category)
                    }
                    if let note {
                        NotePreview(note: note)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(entry.date, format: .dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.confidence < 0.8 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("신뢰도 낮음")
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
