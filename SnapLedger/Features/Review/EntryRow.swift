import SwiftUI
import SwiftData

struct EntryRow: View {
    let entry: ParsedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.merchant)
                    .font(.body)
                Spacer()
                Text("\(entry.amount.formatted(.number))원")
                    .font(.body.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(entry.date, format: .dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let category = entry.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: .capsule)
                }
                if entry.confidence < 0.8 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("신뢰도 낮음")
                }
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

/// Pairs a swipe-saved entry with its reconciled-month warning text.
struct ReconciledSwipeContext: Identifiable {
    let entry: ParsedEntry
    let message: String
    var id: PersistentIdentifier { entry.persistentModelID }
}
