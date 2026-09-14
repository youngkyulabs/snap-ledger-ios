import Foundation

/// Escapes CSV fields containing commas, quotes, or newlines.
enum CSVField {
    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        if needsQuoting {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
