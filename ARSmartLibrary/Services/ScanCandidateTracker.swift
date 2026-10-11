import Foundation

struct ScanCandidateTracker {
    static let minimumConfidence = 0.58
    static let minimumExactConfidence = 0.76
    static let minimumExactOCRConfidence = 0.75
    static let minimumExactTitleCoverage = 0.8

    private(set) var candidateID: String?
    private(set) var observationCount = 0
    private(set) var minimumObservedConfidence: Double?
    private(set) var minimumObservedOCRConfidence: Double?
    private(set) var minimumObservedTitleCoverage: Double?
    private var lastTimestamp: TimeInterval?

    var supportsExactMatch: Bool {
        observationCount >= 2
            && minimumObservedConfidence.map { $0 >= Self.minimumExactConfidence } == true
            && minimumObservedOCRConfidence.map { $0 >= Self.minimumExactOCRConfidence } == true
            && minimumObservedTitleCoverage.map { $0 >= Self.minimumExactTitleCoverage } == true
    }

    mutating func observe(
        candidateID: String?,
        matchConfidence: Double,
        titleOCRConfidence: Double,
        localizedTitleCoverage: Double = 1,
        at timestamp: TimeInterval
    ) -> Bool {
        guard
            let candidateID,
            matchConfidence >= Self.minimumConfidence,
            titleOCRConfidence.isFinite,
            localizedTitleCoverage.isFinite,
            timestamp.isFinite
        else {
            reset()
            return false
        }

        let continuesRecentCandidate = self.candidateID == candidateID
            && lastTimestamp.map { timestamp >= $0 && timestamp - $0 <= 1.6 } == true

        self.candidateID = candidateID
        observationCount = continuesRecentCandidate ? observationCount + 1 : 1
        minimumObservedConfidence = continuesRecentCandidate
            ? min(minimumObservedConfidence ?? matchConfidence, matchConfidence)
            : matchConfidence
        minimumObservedOCRConfidence = continuesRecentCandidate
            ? min(minimumObservedOCRConfidence ?? titleOCRConfidence, titleOCRConfidence)
            : titleOCRConfidence
        minimumObservedTitleCoverage = continuesRecentCandidate
            ? min(minimumObservedTitleCoverage ?? localizedTitleCoverage, localizedTitleCoverage)
            : localizedTitleCoverage
        lastTimestamp = timestamp
        return observationCount >= 2
    }

    mutating func reset() {
        candidateID = nil
        observationCount = 0
        minimumObservedConfidence = nil
        minimumObservedOCRConfidence = nil
        minimumObservedTitleCoverage = nil
        lastTimestamp = nil
    }
}
