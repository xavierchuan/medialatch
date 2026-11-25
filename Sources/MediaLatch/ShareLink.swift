import Foundation

enum ShareLink {
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func extract(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let span = Range(match.range, in: text) else { continue }
            let literal = String(text[span])
            guard let url = URLComponents(string: literal),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty else { continue }
            return literal
        }
        return nil
    }
}
