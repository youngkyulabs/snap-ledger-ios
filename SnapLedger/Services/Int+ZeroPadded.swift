import Foundation

extension Int {
    /// Left-pads the decimal digits with zeros to `width`, keeping a leading minus sign (`%0*d` without format strings).
    nonisolated func zeroPadded(_ width: Int) -> String {
        let digits = String(magnitude)
        let sign = self < 0 ? "-" : ""
        let padding = String(repeating: "0", count: Swift.max(0, width - sign.count - digits.count))
        return sign + padding + digits
    }
}
