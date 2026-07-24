import Foundation

enum MorseElement: Equatable {
    case dit
    case dah
    /// 1 dit space between elements of a character.
    case elementGap
    /// 3 dit spaces between characters.
    case charGap
    /// 7 dit spaces between words.
    case wordGap
}

enum MorseCode {

    /// Letters, digits, punctuation, and K3-style prosign characters:
    /// `(`=KN `+`=AR `=`=BT `%`=AS `*`=SK `!`=VE.
    static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.",
        "-": "-....-", "@": ".--.-.", ":": "---...", "'": ".----.",
        "(": "-.--.",   // KN
        "+": ".-.-.",   // AR
        "=": "-...-",   // BT
        "%": ".-...",   // AS
        "*": "...-.-",  // SK
        "!": "...-.",   // VE
    ]

    /// Expand text into timed elements. Unknown characters are skipped;
    /// runs of whitespace produce a single word gap.
    static func elements(for text: String) -> [MorseElement] {
        var out: [MorseElement] = []
        var pendingWordGap = false
        var firstChar = true

        for ch in text.uppercased() {
            if ch.isWhitespace {
                if !firstChar { pendingWordGap = true }
                continue
            }
            guard let pattern = table[ch] else { continue }

            if pendingWordGap {
                out.append(.wordGap)
                pendingWordGap = false
            } else if !firstChar {
                out.append(.charGap)
            }
            firstChar = false

            for (i, symbol) in pattern.enumerated() {
                if i > 0 { out.append(.elementGap) }
                out.append(symbol == "." ? .dit : .dah)
            }
        }
        return out
    }
}
