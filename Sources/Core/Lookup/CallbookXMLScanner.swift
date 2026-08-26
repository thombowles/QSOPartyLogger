import Foundation

/// Flattens a callbook response into leaf-element text keyed by lowercased
/// element name — both services are one level of leaves inside wrapper
/// elements (`Session`/`Callsign`, `session`/`search`), and neither nests
/// leaves, so a flat map loses nothing. Namespace-tolerant by construction:
/// names are matched without prefixes and case-insensitively, because the
/// live servers already run ahead of both published specs
/// (docs/research/callbook/SOURCES.md).
final class CallbookXMLScanner: NSObject, XMLParserDelegate {
    private(set) var values: [String: String] = [:]
    /// Wrapper elements seen, lowercased — how a caller tells a response
    /// with a `<Callsign>`/`<search>` block from one without.
    private(set) var wrappers: Set<String> = []
    private var text = ""
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        depth += 1
        if depth == 2 { wrappers.insert(name.lowercased()) }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        // Leaves live at depth 3 (root > wrapper > leaf). Leaf names do not
        // collide across the wrappers either service sends, so a flat
        // last-writer map is faithful for an advisory record.
        if depth == 3 {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values[name.lowercased()] = trimmed }
        }
        text = ""
        depth -= 1
    }

    static func scan(_ data: Data) throws -> CallbookXMLScanner {
        let scanner = CallbookXMLScanner()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        guard parser.parse() else {
            throw CallbookParseError.malformed(
                parser.parserError?.localizedDescription ?? "unparseable XML")
        }
        return scanner
    }
}

enum CallbookParseError: Error, Equatable {
    case malformed(String)
}

/// Strict query encoding for both services' URLs. `URLComponents` leaves
/// `/` and `;` legal inside a query, but QRZ's separators *are* `;`/`&` and
/// its documented examples carry plain values only — so every value is
/// reduced to unreserved characters, which both servers must decode.
enum CallbookQuery {
    static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func url(base: String, items: [(String, String)]) -> URL {
        let query = items.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(base)?\(query)")!
    }
}
