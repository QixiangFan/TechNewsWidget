import Foundation

extension String {
    /// Turns feed / HTML text into a single display line: strips tags, decodes
    /// entities, collapses whitespace and truncates with an ellipsis.
    func cleanedText(maxLength: Int) -> String {
        var text = self
        if text.contains("<") {
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        if text.contains("&") {
            text = text.decodingHTMLEntities()
        }
        text = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.count > maxLength {
            text = String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    /// Decodes the named entities that show up in feed titles plus numeric ones (`&#39;`, `&#x2019;`).
    func decodingHTMLEntities() -> String {
        guard let regex = try? NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);") else {
            return self
        }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
            "ldquo": "“", "rdquo": "”", "middot": "·",
        ]
        var result = ""
        var cursor = startIndex
        let nsString = self as NSString
        for match in regex.matches(in: self, range: NSRange(location: 0, length: nsString.length)) {
            guard let whole = Range(match.range, in: self), let nameRange = Range(match.range(at: 1), in: self) else {
                continue
            }
            let name = self[nameRange]
            let replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                replacement = named[String(name)]
            }
            result += self[cursor..<whole.lowerBound]
            result += replacement ?? String(self[whole])
            cursor = whole.upperBound
        }
        result += self[cursor...]
        return result
    }
}
