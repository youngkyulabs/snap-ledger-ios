import Foundation

enum CSVParser {
    static func parse(_ raw: String) -> [[String]] {
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
        return rows
    }
}
