import SwiftUI

extension ReconciliationVerdict.Tone {
    /// Maps reconciliation verdict tone to UI tint color.
    var color: Color {
        switch self {
        case .balanced: .green
        case .off: .orange
        case .inProgress: .secondary
        }
    }
}
