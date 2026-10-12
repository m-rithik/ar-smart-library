import ARKit
import AVFoundation
import RealityKit
import SwiftUI
import Vision

// UI state is mutated on the main queue; scan cadence flags are confined to sessionQueue.
final class ARSessionController: NSObject, ObservableObject, @unchecked Sendable {
    let librarySpace: LibrarySpaceController
    @Published private(set) var selectedBook: Book?
    @Published private(set) var recommendations: [BookRecommendation] = []
    @Published private(set) var recommendationIntent: RecommendationIntent = .similar
    @Published private(set) var useCase: LibraryUseCase = .identify
    @Published private(set) var comparison: BookComparison?
    @Published private(set) var scanPolicy: ScanPolicy?
    @Published private(set) var matchConfidence = 0.0
    @Published private(set) var anchorScreenPosition: CGPoint?
    @Published private(set) var statusMessage = "Point the reticle at a book title"
    @Published private(set) var isLiDARAvailable = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var meshVisible = false
    @Published private(set) var sessionFailureMessage: String?

    var isARSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    var canUseAR: Bool { isARSupported && !permissionDenied && sessionFailureMessage == nil }

    private weak var arView: ARView?
    @MainActor private var catalog: [Book]
    @MainActor private(set) var matcher: BookMatcher
    private var visionCustomWords: [String]
    private let recommendationEngine = RecommendationEngine()
    private let sessionQueue = DispatchQueue(label: "com.rithikmeedinti.ARSmartLibrary.session")
    private let visionQueue = DispatchQueue(label: "com.rithikmeedinti.ARSmartLibrary.vision", qos: .userInitiated)

    private var visionInFlight = false
    private var scanEnabled = true
    private var sessionStarted = false
    private var viewportSize = CGSize.zero
    private var lastVisionTimestamp: TimeInterval = 0
    private var lastProjectionTimestamp: TimeInterval = 0
    private var candidateTracker = ScanCandidateTracker()
    private(set) var isTrackingNormally = false
    private var activeAnchor: AnchorEntity?
    private var anchorWorldPosition: SIMD3<Float>?
    private var activeConfiguration: ARWorldTrackingConfiguration?
    private var spaceWorkflowActive = false
    private var minimumFrameTimestamp: TimeInterval = 0
    private var lastTrackingFrameTimestamp: TimeInterval = 0

    @MainActor
    override convenience init() {
        self.init(customBookStore: CustomBookStore())
    }

    @MainActor
    init(customBookStore: CustomBookStore?, spaceStore: LibrarySpaceStore? = nil) {
        librarySpace = LibrarySpaceController(
            catalog: BookCatalog.load(), store: spaceStore, customBookStore: customBookStore
        )
        let loadedCatalog = librarySpace.catalog
        catalog = loadedCatalog
        matcher = BookMatcher(books: loadedCatalog)
        visionCustomWords = loadedCatalog.flatMap { [$0.title, $0.author] }
        super.init()

        librarySpace.restartSession = { [weak self] in self?.restartARSpace() }
        librarySpace.onCatalogChanged = { [weak self] in self?.updateCatalog($0) }
        librarySpace.onWorkflowChanged = { [weak self] in
            guard let self else { return }
            self.clearSelection()
            let busy = self.librarySpace.isBusyWithSpace
            self.sessionQueue.async { [weak self] in self?.spaceWorkflowActive = busy }
        }

        if loadedCatalog.isEmpty {
            statusMessage = "Book catalog could not be loaded"
        }
    }

    @MainActor
    private func updateCatalog(_ books: [Book]) {
        catalog = books
        matcher = BookMatcher(books: books)
        candidateTracker.reset()
        minimumFrameTimestamp = max(minimumFrameTimestamp, arView?.session.currentFrame?.timestamp ?? 0, lastTrackingFrameTimestamp)
        let words = books.flatMap { [$0.title, $0.author] }
        sessionQueue.async { [weak self] in self?.visionCustomWords = words }
        if let selectedBook {
            recommendations = recommendationEngine.recommendations(
                for: selectedBook, from: books, intent: recommendationIntent
            )
        }
    }

    @MainActor
    func attach(to arView: ARView) {
        self.arView = arView
        librarySpace.attach(to: arView)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.delegateQueue = sessionQueue

        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            startSession()
        }
    }

    @MainActor
    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        sessionQueue.async { [weak self] in
            self?.viewportSize = size
        }
    }

    @MainActor
    func requestCameraAccess() async {
        guard isARSupported else {
            statusMessage = "AR needs a compatible iPhone. You can still browse the library."
            return
        }
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let isAuthorized: Bool

        switch authorizationStatus {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }

        permissionDenied = !isAuthorized
        if isAuthorized {
            startSession()
        } else {
            statusMessage = "Camera access is required"
        }
    }

    @MainActor
    func clearSelection() {
        useCase = .identify
        recommendationIntent = .similar
        resetScanResult()
    }

    @MainActor
    func updateRecommendationIntent(_ intent: RecommendationIntent) {
        recommendationIntent = intent
        guard let selectedBook else {
            return
        }
        recommendations = recommendationEngine.recommendations(
            for: selectedBook,
            from: catalog,
            intent: intent
        )
    }

    @MainActor
    func startFinding(_ book: Book) {
        if librarySpace.space?.placement(for: book.id) != nil {
            librarySpace.navigate(to: book)
            return
        }
        verifyLocatedBook(book)
    }

    @MainActor
    func verifyLocatedBook(_ book: Book) {
        librarySpace.cancelNavigation()
        librarySpace.setAdminMode(false)
        sessionQueue.async { [weak self] in self?.spaceWorkflowActive = false }
        useCase = .find(target: book)
        recommendationIntent = .similar
        resetScanResult(status: "Find \(book.title) on the shelf")
    }

    @MainActor
    func startComparison() {
        guard let selectedBook else {
            return
        }
        useCase = .compare(seed: selectedBook)
        recommendationIntent = .similar
        resetScanResult(status: "Scan a second book to compare")
    }

    @MainActor
    private func resetScanResult(status: String? = nil) {
        minimumFrameTimestamp = max(minimumFrameTimestamp, arView?.session.currentFrame?.timestamp ?? 0, lastTrackingFrameTimestamp)
        selectedBook = nil
        recommendations = []
        scanPolicy = nil
        matchConfidence = 0
        comparison = nil
        anchorScreenPosition = nil
        statusMessage = status ?? (
            catalog.isEmpty
                ? "Book catalog could not be loaded"
                : "Point the reticle at a book title"
        )
        candidateTracker.reset()
        activeAnchor?.removeFromParent()
        activeAnchor = nil
        anchorWorldPosition = nil
        sessionQueue.async { [weak self] in
            self?.scanEnabled = true
        }
    }

    @MainActor
    func toggleMeshVisualization() {
        guard isLiDARAvailable, let arView else {
            return
        }

        meshVisible.toggle()
        if meshVisible {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    @MainActor
    func pause() {
        suspendTracking()
        arView?.session.pause()
        sessionStarted = false
        librarySpace.suspendGuidance()
    }

    @MainActor
    private func suspendTracking() {
        minimumFrameTimestamp = max(minimumFrameTimestamp, arView?.session.currentFrame?.timestamp ?? 0, lastTrackingFrameTimestamp)
        isTrackingNormally = false
        candidateTracker.reset()
        activeAnchor?.isEnabled = false
        anchorScreenPosition = nil
    }

    @MainActor
    @discardableResult
    func updateTrackingReadiness(_ state: ARCamera.TrackingState, at timestamp: TimeInterval) -> Bool {
        guard timestamp > minimumFrameTimestamp, timestamp > lastTrackingFrameTimestamp else { return false }
        lastTrackingFrameTimestamp = timestamp
        if case .normal = state {
            // A resumed session may deliver normal frames without a tracking-state change.
            if !isTrackingNormally, selectedBook == nil {
                statusMessage = catalog.isEmpty
                    ? "Book catalog could not be loaded"
                    : "Point the reticle at a book title"
            }
            isTrackingNormally = true
            activeAnchor?.isEnabled = true
        } else {
            suspendTracking()
        }
        return true
    }

    @MainActor
    private func restartARSpace() {
        arView?.session.pause()
        sessionStarted = false
        activeConfiguration = nil
        sessionFailureMessage = nil
        clearSelection()
        startSession()
    }

    @MainActor
    private func startSession() {
        guard isARSupported else {
            statusMessage = "AR world tracking is unavailable"
            return
        }
        guard let arView, sessionFailureMessage == nil,
              UIApplication.shared.applicationState == .active,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard !sessionStarted else {
            return
        }

        isTrackingNormally = false

        if let activeConfiguration {
            // Resume the same coordinate frame after backgrounding.
            arView.session.run(activeConfiguration)
            sessionStarted = true
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        let supportsMesh = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        if supportsMesh {
            configuration.sceneReconstruction = .meshWithClassification
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        isLiDARAvailable = supportsMesh && (
            configuration.frameSemantics.contains(.smoothedSceneDepth)
                || configuration.frameSemantics.contains(.sceneDepth)
        )
        if catalog.isEmpty {
            statusMessage = "Book catalog could not be loaded"
        } else {
            statusMessage = isLiDARAvailable
                ? "Point the reticle at a book title"
                : "LiDAR unavailable; using AR plane estimates"
        }

        librarySpace.prepareConfiguration(configuration)
        activeConfiguration = configuration
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        sessionStarted = true
    }

    @MainActor
    func retryARSession() {
        guard sessionFailureMessage != nil else { return }
        librarySpace.recoverAfterSessionFailure()
        statusMessage = librarySpace.message
    }

    @MainActor
    private func consumeRecognizedLines(
        _ lines: [RecognizedLine],
        sourceFrame: ARFrame,
        session: ARSession,
        regionOfInterest: CGRect
    ) {
        guard sessionStarted, canUseAR, isTrackingNormally, selectedBook == nil, !librarySpace.isBusyWithSpace,
              sourceFrame.timestamp > minimumFrameTimestamp else {
            candidateTracker.reset()
            return
        }

        guard let match = matcher.bestMatch(for: lines) else {
            _ = candidateTracker.observe(
                candidateID: nil,
                matchConfidence: 0,
                titleOCRConfidence: 0,
                localizedTitleCoverage: 0,
                at: sourceFrame.timestamp
            )
            if !lines.isEmpty {
                switch useCase {
                case .identify:
                    statusMessage = "No catalog match—move closer"
                case let .find(target):
                    statusMessage = "Keep looking for \(target.title)"
                case let .compare(seed):
                    statusMessage = "Scan a book other than \(seed.title)"
                }
            }
            return
        }

        switch useCase {
        case .identify:
            break
        case let .find(target) where match.book.id != target.id:
            candidateTracker.reset()
            statusMessage = "That is \(match.book.title)—keep looking for \(target.title)"
            return
        case let .compare(seed) where match.book.id == seed.id:
            candidateTracker.reset()
            statusMessage = "Choose a different book from \(seed.title)"
            return
        case .find, .compare:
            break
        }

        let isStable = candidateTracker.observe(
            candidateID: match.book.id,
            matchConfidence: match.confidence,
            titleOCRConfidence: match.titleOCRConfidence,
            localizedTitleCoverage: match.localizedTitleCoverage,
            at: sourceFrame.timestamp
        )

        guard match.confidence >= ScanCandidateTracker.minimumConfidence else {
            statusMessage = "Possible \(match.book.title)—move closer"
            return
        }

        guard isStable else {
            statusMessage = "Hold steady on \(match.book.title)"
            return
        }

        let imagePoint = ScanTarget.rawImagePoint(
            fromROIVisionPoint: match.visionTargetPoint,
            regionOfInterest: regionOfInterest
        )
        guard
            CGRect(x: 0, y: 0, width: 1, height: 1).contains(imagePoint),
            let measurement = spatialMeasurement(
                in: sourceFrame,
                at: imagePoint,
                session: session
            )
        else {
            statusMessage = "Aim at a flat shelf or cover and hold steady"
            return
        }

        let policy: ScanPolicy = candidateTracker.supportsExactMatch && measurement.quality == .high
            ? .exact
            : .region

        selectedBook = match.book
        switch useCase {
        case .identify, .find:
            recommendations = recommendationEngine.recommendations(
                for: match.book,
                from: catalog,
                intent: recommendationIntent
            )
        case let .compare(seed):
            recommendations = []
            comparison = recommendationEngine.comparison(
                between: seed,
                and: match.book,
                in: catalog
            )
        }
        scanPolicy = policy
        matchConfidence = candidateTracker.minimumObservedConfidence ?? match.confidence
        switch useCase {
        case .identify:
            statusMessage = "\(policy.title): \(match.book.title)"
        case .find:
            statusMessage = "Found \(match.book.title)"
        case let .compare(seed):
            statusMessage = "Compared \(seed.title) and \(match.book.title)"
        }
        placeAnchor(at: measurement.position, policy: policy)
        sessionQueue.async { [weak self] in
            self?.scanEnabled = false
        }
    }

    @MainActor
    private func placeAnchor(at position: SIMD3<Float>, policy: ScanPolicy) {
        guard let arView else {
            return
        }

        activeAnchor?.removeFromParent()

        let anchor = AnchorEntity(world: position)
        let markerRadius: Float = policy == .exact ? 0.018 : 0.055
        let markerColor: UIColor = policy == .exact
            ? UIColor.systemGreen.withAlphaComponent(0.9)
            : UIColor.systemOrange.withAlphaComponent(0.45)
        let marker = ModelEntity(
            mesh: .generateSphere(radius: markerRadius),
            materials: [SimpleMaterial(color: markerColor, isMetallic: false)]
        )
        marker.name = "book-marker"
        anchor.name = "book-anchor"
        anchor.addChild(marker)
        arView.scene.addAnchor(anchor)

        activeAnchor = anchor
        anchorWorldPosition = position
        updateAnchorProjection()
    }

    @MainActor
    private func updateAnchorProjection() {
        guard isTrackingNormally, let arView, let anchorWorldPosition,
              let frame = arView.session.currentFrame,
              (frame.camera.transform.inverse * SIMD4(anchorWorldPosition, 1)).z < 0 else {
            anchorScreenPosition = nil
            return
        }
        anchorScreenPosition = arView.project(anchorWorldPosition)
    }

    private func scanGeometry(in frame: ARFrame, viewportSize: CGSize) -> FrameScanGeometry? {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return nil
        }

        let targetRect = ScanTarget.viewRect(in: viewportSize)
        let normalizedViewRect = CGRect(
            x: targetRect.minX / viewportSize.width,
            y: targetRect.minY / viewportSize.height,
            width: targetRect.width / viewportSize.width,
            height: targetRect.height / viewportSize.height
        )
        let viewToImage = frame
            .displayTransform(for: .portrait, viewportSize: viewportSize)
            .inverted()
        let imageRect = normalizedViewRect.applying(viewToImage).standardized
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let boundedImageRect = imageRect.intersection(unitRect)

        guard
            !boundedImageRect.isNull,
            boundedImageRect.width > 0,
            boundedImageRect.height > 0
        else {
            return nil
        }

        // ARFrame image coordinates use an upper-left origin. Vision's portrait-right
        // coordinates use a lower-left origin, so rotation swaps the rectangle axes.
        let visionRegion = CGRect(
            x: 1 - boundedImageRect.maxY,
            y: 1 - boundedImageRect.maxX,
            width: boundedImageRect.height,
            height: boundedImageRect.width
        ).intersection(unitRect)

        guard visionRegion.width > 0, visionRegion.height > 0 else {
            return nil
        }

        return FrameScanGeometry(visionRegion: visionRegion)
    }

    private func spatialMeasurement(
        in frame: ARFrame,
        at imagePoint: CGPoint,
        session: ARSession
    ) -> SpatialMeasurement? {
        if let depthMeasurement = DepthSampler.measurement(in: frame, at: imagePoint) {
            return depthMeasurement
        }

        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            let query = frame.raycastQuery(from: imagePoint, allowing: target, alignment: .any)
            if let result = session.raycast(query).first {
                return SpatialMeasurement(
                    position: result.worldTransform.translation,
                    quality: .medium
                )
            }
        }

        return nil
    }

    private func recognizeText(
        in frame: ARFrame,
        regionOfInterest: CGRect,
        session: ARSession,
        customWords: [String]
    ) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.customWords = customWords
        request.minimumTextHeight = 0.018
        request.regionOfInterest = regionOfInterest

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 else {
                    return nil
                }
                return RecognizedLine(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    boundingBox: observation.boundingBox
                )
            }

            DispatchQueue.main.async { [weak self] in
                self?.consumeRecognizedLines(
                    lines,
                    sourceFrame: frame,
                    session: session,
                    regionOfInterest: regionOfInterest
                )
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Text recognition failed—try again"
            }
        }
    }
}

extension ARSessionController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if frame.timestamp - lastProjectionTimestamp >= 0.1 {
            lastProjectionTimestamp = frame.timestamp
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessionStarted, self.sessionFailureMessage == nil,
                      self.updateTrackingReadiness(frame.camera.trackingState, at: frame.timestamp) else { return }
                self.librarySpace.update(frame: frame)
                self.updateAnchorProjection()
            }
        }
        guard case .normal = frame.camera.trackingState else {
            return
        }

        guard
            scanEnabled,
            !spaceWorkflowActive,
            !visionInFlight,
            frame.timestamp - lastVisionTimestamp >= 0.75
        else {
            return
        }

        guard let geometry = scanGeometry(in: frame, viewportSize: viewportSize) else {
            return
        }

        visionInFlight = true
        lastVisionTimestamp = frame.timestamp
        let sourceFrame = frame
        let customWords = visionCustomWords

        visionQueue.async { [weak self] in
            self?.recognizeText(
                in: sourceFrame,
                regionOfInterest: geometry.visionRegion,
                session: session,
                customWords: customWords
            )
            self?.sessionQueue.async { [weak self] in
                self?.visionInFlight = false
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.suspendTracking()
            self.librarySpace.suspendGuidance()
            self.statusMessage = "AR session paused"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.statusMessage = "Look around to recognize the room again"
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.sessionStarted = false
            self.isTrackingNormally = false
            self.clearSelection()
            self.librarySpace.suspendGuidance()

            self.sessionFailureMessage = error.localizedDescription
            self.statusMessage = "AR stopped. Retry tracking or browse the library."
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let trackingMessage: String?
        switch camera.trackingState {
        case .normal:
            trackingMessage = nil
        case .notAvailable:
            trackingMessage = "AR tracking unavailable"
        case let .limited(reason):
            switch reason {
            case .initializing:
                trackingMessage = "Initializing AR tracking"
            case .excessiveMotion:
                trackingMessage = "Move the phone more slowly"
            case .insufficientFeatures:
                trackingMessage = "Aim at a textured shelf or cover"
            case .relocalizing:
                trackingMessage = "Rebuilding AR tracking"
            @unknown default:
                trackingMessage = "AR tracking is limited"
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionStarted, self.sessionFailureMessage == nil else {
                return
            }

            if let trackingMessage {
                self.suspendTracking()
                self.librarySpace.suspendGuidance()
                self.statusMessage = trackingMessage
            } else {
                self.isTrackingNormally = true
                self.activeAnchor?.isEnabled = true
                if self.selectedBook == nil {
                    self.statusMessage = self.catalog.isEmpty
                        ? "Book catalog could not be loaded"
                        : "Point the reticle at a book title"
                }
            }
        }
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }
}

private struct FrameScanGeometry {
    let visionRegion: CGRect
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
