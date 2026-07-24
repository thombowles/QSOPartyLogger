import Foundation

/// Telnet-level details of talking to a DX cluster node.
enum ClusterProtocol {

    /// Pull complete lines out of a receive buffer, leaving any partial line
    /// (and the node's unterminated prompt) behind.
    ///
    /// Splits on unicode scalars rather than Characters: Swift stores "\r\n"
    /// as a *single* Character that compares equal to neither "\r" nor "\n",
    /// so Character-wise scanning silently finds no line breaks at all on the
    /// CRLF endings every cluster node uses.
    static func takeLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()

        for scalar in buffer.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                let line = String(current).trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { lines.append(line) }
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        // Whatever trails the last terminator is an incomplete line — keep it
        // for the next chunk (this is also where the login prompt lands).
        buffer = String(current)
        return lines
    }

    /// Is the node sitting at a login prompt right now?
    ///
    /// Only the tail of the stream counts, and only a genuine prompt: CC
    /// Cluster's banner says "Please login with a callsign…" many lines
    /// before it actually asks, and answering that early means the real
    /// prompt never gets a reply (VE7CC symptom: connected, zero spots).
    static func isAwaitingLogin(_ stream: String) -> Bool {
        // Nodes print the prompt without a newline, so look at what trails
        // the last line break.
        let tail = stream
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""

        guard tail.hasSuffix(":") else { return false }
        let prompt = String(tail.dropLast()).trimmingCharacters(in: .whitespaces)
        return prompt.hasSuffix("login")
            || prompt.hasSuffix("call")
            || prompt.hasSuffix("callsign")
            || prompt.hasSuffix("your call")
    }

    /// Strip telnet (RFC 854) negotiation from a chunk, returning the plain
    /// text plus any bytes we owe the server. Nodes fronted by a real telnetd
    /// negotiate options; unanswered offers can stall a session, and the raw
    /// IAC bytes would otherwise corrupt spot lines.
    static func stripTelnet(_ data: Data) -> (text: String, reply: Data) {
        let iac: UInt8 = 255, dont: UInt8 = 254, doByte: UInt8 = 253
        let wont: UInt8 = 252, will: UInt8 = 251, sb: UInt8 = 250, se: UInt8 = 240

        var out: [UInt8] = []
        var reply: [UInt8] = []
        var index = data.startIndex

        while index < data.endIndex {
            let byte = data[index]
            guard byte == iac, data.index(after: index) < data.endIndex else {
                if byte != iac { out.append(byte) }
                index = data.index(after: index)
                continue
            }
            let command = data[data.index(after: index)]
            switch command {
            case iac:  // escaped literal 0xFF
                out.append(iac)
                index = data.index(index, offsetBy: 2)
            case will, doByte:
                // Refuse every option — we're a plain line-mode client.
                if data.index(index, offsetBy: 2) < data.endIndex {
                    let option = data[data.index(index, offsetBy: 2)]
                    reply += [iac, command == will ? dont : wont, option]
                }
                index = data.index(index, offsetBy: min(3, data.distance(from: index, to: data.endIndex)))
            case wont, dont:
                index = data.index(index, offsetBy: min(3, data.distance(from: index, to: data.endIndex)))
            case sb:
                // Skip through IAC SE.
                var scan = data.index(index, offsetBy: 2)
                while scan < data.endIndex {
                    if data[scan] == iac, data.index(after: scan) < data.endIndex,
                       data[data.index(after: scan)] == se {
                        scan = data.index(scan, offsetBy: 2)
                        break
                    }
                    scan = data.index(after: scan)
                }
                index = scan
            default:
                index = data.index(index, offsetBy: 2)
            }
        }

        let text = String(decoding: out, as: UTF8.self)
        return (text, Data(reply))
    }
}
