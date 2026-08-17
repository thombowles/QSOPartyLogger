import Foundation

/// A final-score factor as an **exact rational**.
///
/// Two sponsors print one that is not a whole number, with the identical
/// values. Vermont rule 7(D)(1): *"If all QSO's were made using more than 5W
/// and less than or equal to 150W output, multiply your score by 1.5"*.
/// Wisconsin's POWER LEVEL table: *"Low — 5 to 100 watts — Power Mult = 1.5"*.
/// While this was `Int`, neither party could ship a power multiplier at all,
/// because ×1 for low power understates a third of the score while looking
/// right — the failure the constitution's preamble is written against.
///
/// Numerator over denominator rather than a `Double`, so the score stays
/// integer arithmetic end to end: `applied(to:)` resolves the fraction **once**
/// and there is no floating-point residue to put a `CLAIMED-SCORE:` one point
/// away from the sponsor's own arithmetic.
struct ScoreFactor: Equatable, Hashable, Sendable {
    /// Always in lowest terms, with a positive denominator.
    let numerator: Int
    let denominator: Int

    /// The factor a party without `scoreMultipliers` scores under — every
    /// party in the catalogue before this type existed.
    static let one = ScoreFactor(1)

    /// The most decimal places a party file may carry. Well past anything a
    /// sponsor prints (1.5 is the whole of it so far), and short enough that a
    /// value which reached us through a binary float cannot smuggle in a
    /// 17-digit denominator.
    static let maxFractionDigits: Int16 = 6

    init(_ whole: Int) {
        numerator = whole
        denominator = 1
    }

    init(numerator: Int, denominator: Int) {
        precondition(denominator != 0, "a score factor cannot have a zero denominator")
        let sign = denominator < 0 ? -1 : 1
        let divisor = Self.greatestCommonDivisor(abs(numerator), abs(denominator))
        self.numerator = sign * numerator / divisor
        self.denominator = sign * denominator / divisor
    }

    /// A decimal as a sponsor printed it — 2, 1.5, 1.25 — as an exact fraction.
    init(_ decimal: Decimal) {
        var scaled = Self.rounded(decimal, places: Self.maxFractionDigits)
        var denominator = 1
        var places: Int16 = 0
        while !Self.isWholeNumber(scaled), places < Self.maxFractionDigits {
            scaled *= 10
            denominator *= 10
            places += 1
        }
        self.init(numerator: NSDecimalNumber(decimal: scaled).intValue, denominator: denominator)
    }

    /// Does this factor leave the score alone? (Nothing is shown for it, and
    /// every party that ships no `scoreMultipliers` is here.)
    var isOne: Bool { numerator == 1 && denominator == 1 }

    /// The whole number this factor is, or `nil` where it is a fraction —
    /// which is every factor in the catalogue but Vermont's and Wisconsin's.
    var wholeNumber: Int? { denominator == 1 ? numerator : nil }

    var isWholeNumber: Bool { denominator == 1 }

    /// `value × self`, resolved **down** to a whole number.
    ///
    /// **Neither sponsor states a rounding rule for the final score.** Vermont's
    /// only rounding instruction anywhere in its rules is 7(B)(f), on a
    /// fractional *multiplier* count: *"dividing by 3, and rounding down"*.
    /// Wisconsin's rules, multiplier list and Cabrillo guide contain no rounding
    /// language at all. Down is therefore the sponsors' own idiom where either
    /// states one, and where neither does it is the direction that cannot
    /// overstate a claimed score — the direction a log checker penalises.
    ///
    /// Called once, on the whole `QSO points × multipliers` product, never step
    /// by step: rounding between the two multiplications would score a
    /// low-power log differently depending on which the sponsor listed first.
    func applied(to value: Int) -> Int {
        let scaled = value * numerator
        let quotient = scaled / denominator
        // `/` truncates toward zero. Scores are never negative, but truncation
        // and flooring part company if one ever is, and "down" means down.
        return scaled < 0 && scaled % denominator != 0 ? quotient - 1 : quotient
    }

    /// The factor as a sponsor prints it: "2", "1.5".
    var displayString: String {
        wholeNumber.map(String.init) ?? "\(Decimal(numerator) / Decimal(denominator))"
    }

    static func * (lhs: ScoreFactor, rhs: ScoreFactor) -> ScoreFactor {
        ScoreFactor(
            numerator: lhs.numerator * rhs.numerator,
            denominator: lhs.denominator * rhs.denominator
        )
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }

    private static func rounded(_ value: Decimal, places: Int16) -> Decimal {
        var result = Decimal()
        var source = value
        NSDecimalRound(&result, &source, Int(places), .plain)
        return result
    }

    private static func isWholeNumber(_ value: Decimal) -> Bool {
        rounded(value, places: 0) == value
    }
}

/// So that `factor(power:station:) == 5` and `categoryFactor: 1` keep reading
/// as the whole numbers they are — which is every party but two.
extension ScoreFactor: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension ScoreFactor: Codable {
    private enum CodingKeys: String, CodingKey {
        case numerator, denominator
    }

    /// Decodes a JSON **number** — `2` or `1.5`, as the sponsor prints it and
    /// as a party file should read. The explicit `{"numerator": 3,
    /// "denominator": 2}` form is also accepted, for a factor whose decimal
    /// does not terminate.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), !single.decodeNil() {
            if let whole = try? single.decode(Int.self) {
                self.init(whole)
                return
            }
            if let decimal = try? single.decode(Decimal.self) {
                self.init(decimal)
                return
            }
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            numerator: try keyed.decode(Int.self, forKey: .numerator),
            denominator: try keyed.decode(Int.self, forKey: .denominator)
        )
    }

    func encode(to encoder: Encoder) throws {
        // Written back the way it was authored wherever the decimal is exact,
        // so a round trip through the catalogue leaves a party file readable.
        if let exact = exactDecimal {
            var container = encoder.singleValueContainer()
            try container.encode(exact)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(numerator, forKey: .numerator)
            try container.encode(denominator, forKey: .denominator)
        }
    }

    /// This factor as a terminating decimal, or `nil` where writing one would
    /// lose the fraction (⅓ and its kin — none in the catalogue, but the check
    /// is what stops a lossy round trip from ever being silent).
    private var exactDecimal: Decimal? {
        let value = Decimal(numerator) / Decimal(denominator)
        return ScoreFactor(value) == self ? value : nil
    }
}
