import Foundation

struct VoiceChunkBuffer {
    private(set) var consumed = 0
    mutating func reset() { consumed = 0 }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{E200}[^\u{E201}]*(?:\u{E201}|$)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "https?://\\S+", with: "リンク", options: .regularExpression)
            .replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
    }
    mutating func take(_ snapshot: String, done: Bool, flush: Bool = false) -> String? {
        let text = Array(Self.clean(snapshot)), left = text.count - consumed
        guard left > 0 else { return nil }
        let count = min(52, left), rest = text[consumed..<(consumed + count)]
        var end: Int?
        for (index, ch) in rest.enumerated() where "。！？!?、,\n".contains(ch) { end = index + 1; break }
        if end == nil && (done || flush || left >= 52) { end = count }
        guard let length = end else { return nil }
        let result = String(text[consumed..<(consumed + length)]); consumed += length
        return result
    }
}
