import XCTest
@testable import QSOPartyLogger

final class PartyCatalogTests: XCTestCase {

    func loadedParty(_ id: String) throws -> PartyDefinition {
        let party = PartyCatalog.party(id: id)
        return try XCTUnwrap(party, "bundled party '\(id)' should load")
    }

    func testBundledPartiesLoad() throws {
        let parties = PartyCatalog.loadBundled()
        XCTAssertEqual(
            Set(parties.map(\.id)),
            ["alqp", "azqp", "bcqp", "coqp", "cqp", "hqp", "iaqp", "idqp", "ilqp", "ksqp", "mdc",
             "meqp",
             "laqp", "mnqp", "msqp", "ncqp", "nhqp", "njqp", "nyqp", "ohqp", "okqp", "paqp", "scqp", "sdqp", "tnqp", "tqp", "vaqp", "vtqp",
             "warun", "wiqp"]
        )
    }

    /// TQP writes the restriction into the QSO points rule itself: a non-Texas
    /// station counts points only "with any Texas station". A non-Texas contact
    /// is therefore worth nothing, and the flag suppresses points, multipliers
    /// and dupe accounting for it.
    func testTexasRestrictsOutOfStateCreditToTexasContacts() throws {
        let tqp = try XCTUnwrap(PartyCatalog.party(id: "tqp"))
        XCTAssertTrue(tqp.outStateWorksHomeStationsOnly)
        XCTAssertEqual(tqp.multipliers.outState.classes, [.county],
                       "a non-Texas entrant's only multiplier is Texas counties")
    }

    /// Which parties restrict an out-of-state entrant to home-state contacts.
    /// The flag suppresses points, multipliers and dupe accounting for every
    /// other row, so a party joining or leaving this list moves scores — it
    /// must be a deliberate edit backed by rule text, never incidental.
    ///
    /// Maine is the standing exception: its out-of-state entrants score each
    /// other, in the sponsor's own wording.
    func testOutOfStateCreditRestrictionPerParty() {
        let unrestricted: Set<String> = ["meqp"]
        for party in PartyCatalog.loadBundled() {
            XCTAssertEqual(
                party.outStateWorksHomeStationsOnly,
                !unrestricted.contains(party.id),
                "\(party.id) changed who an out-of-state entrant may work for credit"
            )
        }
    }

    /// The three parties whose restriction was researched last, each quoting the
    /// sentence that backs it. TQP's is a points rule; the other two are the
    /// party Object, resolved by the standing precedent.
    func testLatelyResearchedRestrictionsKeepTheirMultiplierShape() throws {
        for id in ["alqp", "ksqp", "tqp"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertTrue(party.outStateWorksHomeStationsOnly, id)
            XCTAssertEqual(
                party.multipliers.outState.classes, [.county],
                "\(id): an out-of-state entrant's only multiplier is a home-state county"
            )
        }
    }

    // MARK: Verification status (constitution Article 3)

    /// Every bundled party is either fully verified or explicitly marked
    /// `verified: partial` — the setup sheet drives its warning off this, so a
    /// party silently changing status would silently change the UI.
    func testPartialVerificationStatusPerParty() throws {
        let expectedPartial: Set<String> = [
            "azqp", "hqp", "iaqp", "ilqp", "meqp", "nhqp", "njqp", "nyqp", "paqp",
            "sdqp", "tnqp", "tqp", "vtqp", "mnqp", "bcqp", "scqp", "ncqp", "okqp", "idqp",
            "wiqp", "vaqp", "laqp", "msqp",
        ]
        for party in PartyCatalog.loadBundled() {
            XCTAssertEqual(
                party.isPartiallyVerified,
                expectedPartial.contains(party.id),
                "\(party.id) partial-verification status changed — update the setup sheet "
                    + "expectations and this list deliberately, not incidentally"
            )
        }
    }

    /// Provenance prose must not be able to raise a false warning: the marker is
    /// matched literally, not by searching for the word "partial".
    func testPartialMarkerIsMatchedLiterallyNotByWordSearch() throws {
        let alqp = try loadedParty("alqp")
        XCTAssertFalse(alqp.isPartiallyVerified)

        func party(notes: String) throws -> PartyDefinition {
            let json = """
            {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
            "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
            "dupeScope":"bandMode",
            "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
            "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
            "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}],
            "notes":"\(notes)"}
            """
            return try PartyCatalog.decode(Data(json.utf8))
        }

        XCTAssertFalse(
            try party(notes: "Counties partially rebuilt from the partial county map.")
                .isPartiallyVerified,
            "the word 'partial' in prose must not trigger the warning"
        )
        XCTAssertTrue(try party(notes: "verified: partial - band list unconfirmed.").isPartiallyVerified)
        XCTAssertTrue(try party(notes: "VERIFIED: PARTIAL - shouting still counts.").isPartiallyVerified)
    }

    /// The setup sheet shows the open-question tail inline and hides the
    /// provenance paragraph behind a disclosure, so the split has to be real.
    func testOpenQuestionsAreSeparatedFromProvenance() throws {
        let hqp = try loadedParty("hqp")
        let questions = try XCTUnwrap(hqp.openQuestions, "HQP's window conflict is an open question")
        XCTAssertTrue(questions.hasPrefix("OPEN QUESTION"))
        XCTAssertTrue(questions.contains("info@hawaiiqsoparty.org"))
        XCTAssertFalse(
            questions.contains("Multiplier entities are the 14"),
            "the provenance paragraph must not leak into the inline warning"
        )

        let tnqp = try loadedParty("tnqp")
        XCTAssertTrue(try XCTUnwrap(tnqp.openQuestions).contains("late August 2026"))

        // Fully verified parties have provenance but nothing to act on.
        XCTAssertNil(try loadedParty("mdc").openQuestions)
        XCTAssertNil(try loadedParty("ohqp").openQuestions)
    }

    func testKSQPCountyData() throws {
        let ksqp = try loadedParty("ksqp")
        XCTAssertEqual(ksqp.counties.count, 105)
        XCTAssertEqual(Set(ksqp.counties.map(\.abbr)).count, 105, "abbrs unique")
        XCTAssertEqual(ksqp.county(for: "WYA")?.name, "Wyandotte")
        XCTAssertEqual(ksqp.county(for: "MCP")?.name, "McPherson")
        XCTAssertEqual(ksqp.county(for: "mrn")?.name, "Marion")
        XCTAssertEqual(ksqp.countyAbbrLength, 3)
        XCTAssertEqual(ksqp.homeState, "KS")
        XCTAssertEqual(ksqp.cabrilloContest, "KS-QSO-PARTY")
        XCTAssertEqual(ksqp.points.points(for: .phone), 2)
        XCTAssertEqual(ksqp.points.points(for: .cw), 3)
        XCTAssertEqual(ksqp.points.points(for: .digital), 3)
        XCTAssertEqual(ksqp.oneByOne?.words.count, 4)
        XCTAssertEqual(ksqp.oneByOne?.wildcard, "KS0KS")
        XCTAssertEqual(ksqp.bonuses, [.workStation(call: "KS0KS", points: 100, scope: .once)])
        XCTAssertTrue(ksqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(ksqp.validBands.contains(.m160), "KSQP has no 160m")
    }

    func testTQPCountyData() throws {
        let tqp = try loadedParty("tqp")
        XCTAssertEqual(tqp.counties.count, 254)
        XCTAssertEqual(Set(tqp.counties.map(\.abbr)).count, 254)
        XCTAssertEqual(tqp.county(for: "DSMI")?.name, "Deaf Smith")
        XCTAssertEqual(tqp.county(for: "EPAS")?.name, "El Paso")
        XCTAssertEqual(tqp.county(for: "TGRE")?.name, "Tom Green")
        XCTAssertEqual(tqp.county(for: "BEE")?.name, "Bee")
        XCTAssertEqual(tqp.county(for: "HARR")?.name, "Harris")
        XCTAssertEqual(tqp.county(for: "HRSN")?.name, "Harrison")
        XCTAssertEqual(tqp.countyAbbrLength, 4)
        XCTAssertEqual(tqp.bonuses, [.mobileCountyCount(per: 5, points: 500)])
    }

    func testOutStateTokensExcludeHomeState() throws {
        let ksqp = try loadedParty("ksqp")
        XCTAssertFalse(ksqp.validOutStateTokens.contains("KS"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("TX"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("ON"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("DX"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("DC"))
        XCTAssertEqual(MultClass.canadianProvinces.count, 13)
        XCTAssertEqual(MultClass.usStates.count, 50)
    }

    func testDuplicateAbbreviationRejected() throws {
        let json = """
        {"schemaVersion":1,"id":"bad","name":"Bad","cabrilloContest":"BAD","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"ALL","name":"Other"}]}
        """
        XCTAssertThrowsError(try PartyCatalog.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PartyValidationError, .duplicateAbbreviation("ALL"))
        }
    }

    func testBonusRuleRoundTrip() throws {
        let rules: [BonusRule] = [
            .workStation(call: "KS0KS", points: 100, scope: .once),
            .mobileCountyCount(per: 5, points: 500),
        ]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([BonusRule].self, from: data)
        XCTAssertEqual(decoded, rules)
    }
}
