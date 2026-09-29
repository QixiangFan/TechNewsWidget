import Foundation

extension String {
    /// Turns feed / HTML text into a single display line: strips tags, decodes
    /// entities, collapses whitespace and truncates with an ellipsis.
    func cleanedText(maxLength: Int) -> String {
        plainText().truncated(to: maxLength)
    }

    /// Strips tags, decodes entities and collapses whitespace, without truncating.
    func plainText() -> String {
        var text = self
        if text.contains("<") {
            // Inline tags sit inside a sentence ("现在，<strong>用户</strong>可以") and vanish without
            // a trace, as in a browser; any other tag separates words.
            text = text
                .replacingOccurrences(of: #"(?i)</?(a|abbr|b|cite|code|em|font|i|mark|q|s|small|span|strong|sub|sup|time|u)\b[^>]*>"#,
                                      with: "", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        if text.contains("&") {
            text = text.decodingHTMLEntities()
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cuts the text to `maxLength` characters, ending with an ellipsis when anything was cut.
    func truncated(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Turns a feed description (often a whole article in HTML) into a short plain-text summary.
    /// Keeps the opening paragraphs and drops what is not part of the story: captions, bylines,
    /// image credits, "read more" links, newsletter plugs, paragraphs that only repeat `title`,
    /// datelines such as "IT之家 9 月 30 日消息，" and editor's notes such as "（IT之家注：…）".
    func summaryText(maxLength: Int, droppingTitle title: String = "") -> String {
        let html = replacingOccurrences(of: #"(?is)<(figcaption|script|style)\b.*?</\1>"#, with: " ",
                                        options: .regularExpression)
        let blocks = html
            .replacingOccurrences(of: #"(?i)</?(p|div|br|li|ul|ol|h[1-6]|blockquote|figure|section|table|tr|td)\b[^>]*>"#,
                                  with: "\u{2029}", options: .regularExpression)
            .components(separatedBy: "\u{2029}")

        var summary = ""
        for block in blocks {
            var paragraph = block.plainText()
                .removingReadMoreLink()
                .replacingOccurrences(of: #"^\S{0,12}?\s*\d{1,2}\s*月\s*\d{1,2}\s*日\s*(消息|电|讯)\s*[，,：:]\s*"#,
                                      with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*[（(][^（）()]{0,20}注\s*[：:][^（）()]*[）)]"#, with: "",
                                      options: .regularExpression)
            if summary.isEmpty {
                // A list marker only makes sense between items.
                paragraph = paragraph.replacingOccurrences(of: #"^[·•▪–—-]\s*"#, with: "", options: .regularExpression)
            }
            guard !paragraph.isEmpty, !title.contains(paragraph), !paragraph.isBoilerplate else { continue }
            summary += summary.isEmpty ? paragraph : " " + paragraph
            if summary.count >= maxLength { break }
        }
        return summary.truncated(to: maxLength)
    }

    /// Nil for an empty string, so optional fields never store "".
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    /// Removes a trailing "查看全文" / "Read more" link and WordPress's "[…]"; an ellipsis right
    /// before the link is kept so the cut stays visible.
    private func removingReadMoreLink() -> String {
        let link = #"(查看全文|阅读全文|阅读原文|read more|continue reading)\s*[»›→]*"#
        return replacingOccurrences(of: #"(?i)\s*(\.{3}|…)\s*"# + link + "$", with: "…", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*"# + link + "$", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[(…|\.{3})\]$"#, with: "…", options: .regularExpression)
    }

    /// Paragraphs that are never part of the story: newsletter plugs ("#欢迎关注…"), quoted promos,
    /// image captions ("▲ …"), bylines and credits ("作者｜…", "头图来源：…") and paywall notices.
    private var isBoilerplate: Bool {
        range(of: #"^([#>▲△]|(作者|编辑|撰文|责编|责任编辑|题图|头图|图片|图源|来源|头图来源|图片来源)\s*[｜|:：/]|本文为会员文章)"#,
              options: .regularExpression) != nil
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
