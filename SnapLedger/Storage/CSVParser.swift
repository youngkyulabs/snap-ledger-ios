import Foundation

enum CSVParser {
    struct Output: Equatable {
        let rows: [[String]]
        /// 파일 끝까지 닫히지 않은 따옴표가 있었는지 — 외부 편집기에서
        /// 구조가 깨진 파일의 신호. 이후 행들이 한 필드로 뭉개졌을 수 있다.
        let hasUnterminatedQuote: Bool
    }

    static func parse(_ raw: String) -> [[String]] {
        parseDetailed(raw).rows
    }

    static func parseDetailed(_ raw: String) -> Output {
        var content = raw
        if content.first == "\u{FEFF}" {
            content.removeFirst()
        }

        let chars = Array(content)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                currentField.append(c)
                i += 1
                continue
            }

            switch c {
            case "\"":
                inQuotes = true
            case ",":
                currentRow.append(currentField)
                currentField = ""
            case "\n":
                currentRow.append(currentField)
                rows.append(currentRow)
                currentField = ""
                currentRow = []
            case "\r":
                break
            default:
                currentField.append(c)
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return Output(rows: rows, hasUnterminatedQuote: inQuotes)
    }
}
