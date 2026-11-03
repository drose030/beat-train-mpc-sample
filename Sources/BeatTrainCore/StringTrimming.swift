extension StringProtocol {
    /// The text without leading and trailing whitespace and newlines: what
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` gives, which
    /// FoundationEssentials (the Linux build) does not have.
    func trimmed() -> String {
        guard let first = firstIndex(where: { !$0.isWhitespace }),
              let last = lastIndex(where: { !$0.isWhitespace })
        else {
            return ""
        }
        return String(self[first...last])
    }
}
