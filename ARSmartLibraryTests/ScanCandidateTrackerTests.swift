import XCTest
@testable import ARSmartLibrary

final class ScanCandidateTrackerTests: XCTestCase {
    func testRequiresTwoRecentQualifiedObservations() {
        var tracker = ScanCandidateTracker()

        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 1.0
        ))
        XCTAssertTrue(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 1.75
        ))
        XCTAssertTrue(tracker.supportsExactMatch)
    }

    func testWeakObservationCannotPrimeCandidate() {
        var tracker = ScanCandidateTracker()

        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.57,
            titleOCRConfidence: 0.9,
            at: 1.0
        ))
        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 1.75
        ))
    }

    func testMissResetsCandidate() {
        var tracker = ScanCandidateTracker()

        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 1.0
        ))
        XCTAssertFalse(tracker.observe(
            candidateID: nil,
            matchConfidence: 0,
            titleOCRConfidence: 0,
            at: 1.75
        ))
        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 2.5
        ))
    }

    func testLongGapExpiresCandidate() {
        var tracker = ScanCandidateTracker()

        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 1.0
        ))
        XCTAssertFalse(tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.8,
            titleOCRConfidence: 0.9,
            at: 3.0
        ))
    }

    func testExactSupportUsesWorstConfidenceRegardlessOfOrder() {
        for confidences in [[0.58, 0.9], [0.9, 0.58]] {
            var tracker = ScanCandidateTracker()

            _ = tracker.observe(
                candidateID: "dune",
                matchConfidence: confidences[0],
                titleOCRConfidence: 0.9,
                at: 1.0
            )
            _ = tracker.observe(
                candidateID: "dune",
                matchConfidence: confidences[1],
                titleOCRConfidence: 0.9,
                at: 1.75
            )

            XCTAssertFalse(tracker.supportsExactMatch)
        }
    }

    func testExactSupportRequiresHighOCRInBothObservations() {
        var tracker = ScanCandidateTracker()

        _ = tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.9,
            titleOCRConfidence: 0.7,
            at: 1.0
        )
        _ = tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.9,
            titleOCRConfidence: 0.95,
            at: 1.75
        )

        XCTAssertFalse(tracker.supportsExactMatch)
    }

    func testExactSupportRequiresLocalizedTitleCoverageInBothObservations() {
        var tracker = ScanCandidateTracker()

        _ = tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.9,
            titleOCRConfidence: 0.95,
            localizedTitleCoverage: 0.5,
            at: 1.0
        )
        _ = tracker.observe(
            candidateID: "dune",
            matchConfidence: 0.9,
            titleOCRConfidence: 0.95,
            localizedTitleCoverage: 1,
            at: 1.75
        )

        XCTAssertFalse(tracker.supportsExactMatch)
    }
}
