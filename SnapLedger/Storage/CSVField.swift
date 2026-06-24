import Foundation

/// CSV 필드 이스케이프 — RFC4180.
/// 필드가 쉼표/따옴표/개행(\n,\r)을 포함하면 따옴표로 감싸고 내부 따옴표를 ""로 이스케이프한다.
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
