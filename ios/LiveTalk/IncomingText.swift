import Foundation

enum IncomingText {
    static func parse(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "livetalk", url.host == "read", url.path.isEmpty || url.path == "/",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1, items[0].name == "text",
              let raw = items[0].value else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 12000 else { return nil }
        return text
    }
}
