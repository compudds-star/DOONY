import Foundation

/// Masks sensitive identifiers for display. The raw value stays in the encrypted
/// store; only this masked form is ever rendered by default.
enum Masking {
    /// Shows only the last `visible` characters, e.g. "•••• •••• 1234".
    static func mask(_ value: String, visible: Int = 4) -> String {
        let trimmed = value.filter { !$0.isWhitespace }
        guard trimmed.count > visible else {
            return String(repeating: "•", count: max(trimmed.count, 4))
        }
        let suffix = trimmed.suffix(visible)
        return "•••• " + suffix
    }
}
