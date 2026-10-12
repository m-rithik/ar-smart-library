import ARKit
import CoreImage
import RealityKit
import SwiftUI

/// Owns the saved coordinate system. All UI, map edits and RealityKit mutations run on main.
@MainActor
final class LibrarySpaceController: ObservableObject {
    @Published private(set) var space: LibrarySpace?
    @Published private(set) var isAdmin = false
    @Published private(set) var isLocalized = false
    @Published private(set) var isSaving = false
    @Published private(set) var canSave = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var hasSavedSpace = false
    @Published private(set) var message = "Create a library space in Admin to place your shelves."
    @Published private(set) var mappingStatusText = "Look around the room"
    @Published private(set) var localizationImageData: Data?
    @Published private(set) var targetBook: Book?
    @Published private(set) var guidance: ShelfGuidance?
    @Published private(set) var navigationIssue: ShelfNavigationIssue?
    @Published private(set) var routeStep = ""
    @Published private(set) var isAtShelf = false
    @Published private(set) var shelfScreenPosition: CGPoint?
    @Published private(set) var pendingShelf: ShelfDraft?
    @Published private(set) var recordedStopCount = 0

    @Published private(set) var catalog: [Book]
    @Published private(set) var customBookError: String?
    var restartSession: (() -> Void)?
    var onWorkflowChanged: (() -> Void)?
    var onCatalogChanged: (([Book]) -> Void)?

    private weak var arView: ARView?
    private var store: LibrarySpaceStore
    private let customBookStore: CustomBookStore?
    private var customBooks: [Book] = []
    private var initialMap: ARWorldMap?
    private var isNewCoordinateSpace = false
    private var originWasAdded = false
    private var coordinateEpoch = UUID()
    private var resolvedAnchors: [String: simd_float4x4] = [:]
    private var shelfVisuals: [UUID: AnchorEntity] = [:]
    private var waypointVisual: AnchorEntity?
    private var route: ShelfRouteProgress?
    private var draftStops: [LibraryWaypoint] = []
    private var localizationStartedAt: TimeInterval?
    private var saveID: UUID?
    private var minimumFrameTimestamp: TimeInterval = 0

    var isBusyWithSpace: Bool { isAdmin || targetBook != nil || pendingShelf != nil }
    var hasWorkingChanges: Bool { hasUnsavedChanges || pendingShelf != nil }

    var targetPlacement: LibraryBookPlacement? {
        guard let targetBook else { return nil }
        return space?.placement(for: targetBook.id)
    }

    init(catalog: [Book], store: LibrarySpaceStore? = nil, customBookStore: CustomBookStore? = nil) {
        self.catalog = catalog
        self.store = store ?? LibrarySpaceStore()
        self.customBookStore = customBookStore
        if let customBookStore {
            do {
                customBooks = try customBookStore.load()
                self.catalog.append(contentsOf: customBooks)
            } catch {
                customBookError = "Could not open your saved books. Adding books is disabled to protect the saved file."
            }
        }
        self.store.updateCatalogBookIDs(Set(self.catalog.map(\.id)))
        loadSavedData()
    }

    @discardableResult
    func addCustomBook(
        title: String, author: String, genre: String, summary: String, keywords: String, rating: Double
    ) throws -> Book {
        guard customBookError == nil else { throw CustomBookError.loadFailed }
        guard let customBookStore else { throw CustomBookError.storageUnavailable }
        let book = try CustomBookStore.makeBook(
            title: title, author: author, genre: genre, summary: summary,
            keywords: keywords, rating: rating, existingBooks: catalog
        )
        let updatedCustomBooks = customBooks + [book]
        try customBookStore.save(updatedCustomBooks)
        customBooks = updatedCustomBooks
        catalog.append(book)
        store.updateCatalogBookIDs(Set(catalog.map(\.id)))
        onCatalogChanged?(catalog)
        return book
    }

    func attach(to view: ARView) { arView = view }

    func prepareConfiguration(_ configuration: ARWorldTrackingConfiguration) {
        configuration.initialWorldMap = initialMap
        coordinateEpoch = UUID()
        originWasAdded = false
        resolvedAnchors = [:]
        localizationStartedAt = nil
        suspendGuidance()
        removeVisuals()
    }

    func setAdminMode(_ value: Bool) {
        guard !isSaving, value != isAdmin else { return }
        guard pendingShelf == nil else {
            message = "Finish or cancel the current shelf placement before leaving Admin."
            return
        }
        isAdmin = value
        cancelNavigation()
        removeVisuals()
        onWorkflowChanged?()
    }

    func beginNewSpace(name: String) {
        guard !isSaving, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        space = LibrarySpace(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        initialMap = nil
        isNewCoordinateSpace = true
        isAdmin = true
        hasUnsavedChanges = true
        localizationImageData = nil
        cancelNavigation()
        cancelShelfPlacement()
        message = "Start at the entrance. Scan the room, then add a shelf and record aisle stops."
        onWorkflowChanged?()
        restartSession?()
    }

    @discardableResult
    func restoreSavedSpace() -> Bool {
        guard !isSaving else { return false }
        do {
            guard let saved = try readSavedData() else {
                message = "No saved space is available. Your current work has been kept."
                return false
            }
            let destination = targetBook
            coordinateEpoch = UUID()
            cancelShelfPlacement()
            cancelNavigation()
            applySavedData(saved)
            if let destination, space?.placement(for: destination.id) != nil { targetBook = destination }
            suspendGuidance()
            onWorkflowChanged?()
            restartSession?()
            return true
        } catch {
            message = "Could not restore the saved space: \(error.localizedDescription) Your current work has been kept."
            return false
        }
    }

    /// A fatal AR reset cannot reuse unsaved coordinates in a new origin.
    func recoverAfterSessionFailure() {
        let hadWorkingChanges = hasWorkingChanges
        let destination = targetBook
        // Invalidate an outstanding map capture before replacing its coordinate frame.
        coordinateEpoch = UUID()
        saveID = nil
        isSaving = false
        suspendGuidance()
        cancelShelfPlacement()
        cancelNavigation()
        resolvedAnchors = [:]
        do {
            if let saved = try readSavedData() {
                applySavedData(saved)
                if let destination, space?.placement(for: destination.id) != nil { targetBook = destination }
                if hadWorkingChanges {
                    message = "AR tracking restarted. Unsaved placement changes were discarded; the saved space was restored."
                }
            } else {
                clearSpaceData()
                message = hadWorkingChanges
                    ? "AR tracking restarted. Unsaved placements could not be recovered. Create a space to map the room again."
                    : "AR tracking restarted. Create a library space in Admin to place your shelves."
            }
        } catch {
            clearSpaceData()
            message = "AR tracking restarted, but the saved space could not be opened: \(error.localizedDescription) Create a space to map the room again."
        }
        onWorkflowChanged?()
        restartSession?()
    }

    func beginPlacingShelf(label: String, row: String, width: Float, height: Float, instructions: String) {
        guard isAdmin, space != nil, !isSaving else { return }
        guard pendingShelf == nil else {
            message = "Finish or cancel the current shelf placement before starting another."
            return
        }
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = row.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !row.isEmpty, width.isFinite, height.isFinite,
              (0.2...4).contains(width), (0.1...2).contains(height) else {
            message = "Enter a shelf name, row, and valid dimensions."
            return
        }
        pendingShelf = ShelfDraft(label: label, row: row, width: width, height: height, instructions: instructions)
        draftStops = []
        recordedStopCount = 0
        message = "Record the entrance first, then stops along the aisle to this shelf."
        onWorkflowChanged?()
    }

    func recordRouteStop() {
        guard pendingShelf != nil, !isSaving, isLocalized,
              let frame = arView?.session.currentFrame,
              case .normal = frame.camera.trackingState else {
            message = "Wait until the room is recognized before recording a stop."
            return
        }
        var transform = matrix_identity_float4x4
        transform.columns.3 = frame.camera.transform.columns.3
        if let last = draftStops.last?.position {
            let delta = SIMD2<Float>(transform.columns.3.x - last.x, transform.columns.3.z - last.z)
            guard simd_length(delta) >= 0.5 else {
                message = "Walk at least half a meter before recording the next stop."
                return
            }
        }
        if localizationImageData == nil { localizationImageData = imageData(from: frame) }
        draftStops.append(LibraryWaypoint(worldTransform: transform))
        recordedStopCount = draftStops.count
        message = "Stop \(recordedStopCount) recorded. Add stops at aisle turns; then aim at the shelf row."
    }

    func undoRouteStop() {
        guard !isSaving, !draftStops.isEmpty else { return }
        draftStops.removeLast()
        recordedStopCount = draftStops.count
    }

    func placeShelfAtReticle() {
        guard isAdmin, !isSaving, isLocalized, let draft = pendingShelf,
              let arView, let frame = arView.session.currentFrame,
              case .normal = frame.camera.trackingState else {
            message = "Wait for stable room tracking before placing the shelf."
            return
        }
        guard !draftStops.isEmpty else {
            message = "Record at least the entrance stop before placing this shelf."
            return
        }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let imagePoint = CGPoint(x: 0.5, y: 0.5).applying(
            frame.displayTransform(for: .portrait, viewportSize: arView.bounds.size).inverted()
        )
        let point: SIMD3<Float>?
        let surfaceNormal: SIMD3<Float>?
        if let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .vertical).first {
            point = Self.position(hit.worldTransform)
            // ARKit's plane coordinate system lies in XZ; +Y is its normal.
            let surfaceTransform = (hit.anchor as? ARPlaneAnchor)?.transform ?? hit.worldTransform
            surfaceNormal = SIMD3(surfaceTransform.columns.1.x, surfaceTransform.columns.1.y, surfaceTransform.columns.1.z)
        } else {
            point = DepthSampler.measurement(in: frame, at: imagePoint)?.position
            surfaceNormal = nil
        }
        guard let point else {
            message = "Aim at the center of the shelf row and slowly scan until its surface is detected."
            return
        }
        guard let transform = ShelfPlacement.transform(
            at: point,
            cameraPosition: Self.position(frame.camera.transform),
            surfaceNormal: surfaceNormal
        ) else {
            message = "Step back and scan the front of the shelf until a vertical surface is detected."
            return
        }
        var shelf = LibraryShelf(
            label: draft.label, row: draft.row, instructions: draft.instructions,
            worldTransform: transform, width: draft.width, height: draft.height
        )
        shelf.routeWaypoints = draftStops
        space?.shelves.append(shelf)
        arView.session.add(anchor: ARAnchor(name: Self.shelfName(shelf.id), transform: transform))
        for stop in draftStops {
            if let transform = stop.worldTransform {
                arView.session.add(anchor: ARAnchor(name: Self.waypointName(stop.id), transform: transform))
            }
        }
        hasUnsavedChanges = true
        cancelShelfPlacement()
        let alignmentNote = surfaceNormal == nil
            ? " The row faces the camera because its surface angle was unavailable. Check it from straight ahead; replace the row if needed."
            : ""
        message = "\(shelf.label), \(shelf.row) placed.\(alignmentNote) Open Library to assign books, then save the AR space."
    }

    func cancelShelfPlacement() {
        pendingShelf = nil
        draftStops = []
        recordedStopCount = 0
    }

    func assign(bookID: String, shelfID: UUID, slotLabel: String) {
        guard isAdmin, !isSaving, space != nil, catalog.contains(where: { $0.id == bookID }) else { return }
        do {
            try space?.assign(bookID: bookID, shelfID: shelfID, slotLabel: slotLabel)
            hasUnsavedChanges = true
            message = "Book location assigned. Save the space to keep this change."
        } catch { message = error.localizedDescription }
    }

    func removeBookAssignment(bookID: String) {
        guard isAdmin, !isSaving, space?.placement(for: bookID) != nil else { return }
        space?.removeBookAssignment(bookID: bookID)
        hasUnsavedChanges = true
        message = "Book location removed. Save the space to keep this change."
    }

    func removeShelf(id: UUID) {
        guard isAdmin, !isSaving, let shelf = space?.shelves.first(where: { $0.id == id }) else { return }
        let names = Set([Self.shelfName(id)] + shelf.routeWaypoints.map { Self.waypointName($0.id) })
        if let session = arView?.session {
            for anchor in session.currentFrame?.anchors ?? [] where anchor.name.map(names.contains) == true {
                session.remove(anchor: anchor)
            }
        }
        space?.removeShelf(id: id)
        shelfVisuals.removeValue(forKey: id)?.removeFromParent()
        hasUnsavedChanges = true
        message = "Shelf and its book assignments removed. Save the space to keep this change."
    }

    func saveSpace() {
        guard isAdmin, canSave, pendingShelf == nil, !isSaving, let snapshot = space, let arView,
              let frame = arView.session.currentFrame, case .normal = frame.camera.trackingState else {
            message = "Wait for room alignment and scan more surfaces before saving."
            return
        }
        isSaving = true
        let transaction = UUID()
        saveID = transaction
        let epoch = coordinateEpoch
        let image = localizationImageData
        arView.session.getCurrentWorldMap { [weak self] map, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.saveID == transaction else { return }
                defer {
                    self.isSaving = false
                    self.saveID = nil
                }
                guard epoch == self.coordinateEpoch, self.isLocalized else {
                    self.message = "Tracking changed while saving. Scan the room and save again."
                    return
                }
                guard let map else {
                    self.message = "Could not capture the room: \(error?.localizedDescription ?? "scan more surfaces and retry")."
                    return
                }
                do {
                    try Self.validateAnchors(in: map, for: snapshot)
                    var savedSpace = snapshot
                    for index in savedSpace.shelves.indices {
                        let shelf = savedSpace.shelves[index]
                        if let anchor = map.anchors.first(where: { $0.name == Self.shelfName(shelf.id) }) {
                            savedSpace.shelves[index].transform = Self.values(anchor.transform)
                        }
                        for stopIndex in shelf.routeWaypoints.indices {
                            let stop = shelf.routeWaypoints[stopIndex]
                            if let anchor = map.anchors.first(where: { $0.name == Self.waypointName(stop.id) }) {
                                savedSpace.shelves[index].routeWaypoints[stopIndex].transform = Self.values(anchor.transform)
                            }
                        }
                    }
                    let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    try self.store.save(space: savedSpace, worldMapData: data, localizationImageData: image)
                    self.space = savedSpace
                    self.initialMap = map
                    self.hasSavedSpace = true
                    self.hasUnsavedChanges = false
                    self.message = "\(snapshot.name) saved on this iPhone. Reader mode can now guide to assigned shelves."
                } catch { self.message = "Save failed: \(error.localizedDescription)" }
            }
        }
    }

    func navigate(to book: Book) {
        guard pendingShelf == nil else {
            message = "Finish or cancel the current shelf placement before starting directions."
            return
        }
        guard !isSaving, space?.placement(for: book.id) != nil else {
            message = "An admin must assign this book to a shelf first."
            return
        }
        isAdmin = false
        cancelShelfPlacement()
        cancelNavigation()
        targetBook = book
        routeStep = "Return to the recorded entrance"
        message = isLocalized ? "Follow the recorded aisle stops to your shelf." : "Look around the saved entrance to recognize this room."
        onWorkflowChanged?()
    }

    func cancelNavigation() {
        let wasNavigating = targetBook != nil
        targetBook = nil
        guidance = nil
        navigationIssue = nil
        route = nil
        routeStep = ""
        isAtShelf = false
        shelfScreenPosition = nil
        removeVisuals()
        if wasNavigating { onWorkflowChanged?() }
    }

    func suspendGuidance() {
        minimumFrameTimestamp = arView?.session.currentFrame?.timestamp ?? minimumFrameTimestamp
        isLocalized = false
        canSave = false
        guidance = nil
        navigationIssue = nil
        isAtShelf = false
        shelfScreenPosition = nil
        shelfVisuals.values.forEach { $0.isEnabled = false }
        waypointVisual?.isEnabled = false
    }

    func update(frame: ARFrame) {
        guard let space else { return }
        guard frame.timestamp > minimumFrameTimestamp else { return }
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        switch frame.worldMappingStatus {
        case .mapped: mappingStatusText = "Room mapped"
        case .extending: mappingStatusText = "Mapping more of the room"
        default: mappingStatusText = "Move slowly and scan shelves and walls"
        }
        if isNewCoordinateSpace, normal, !originWasAdded {
            arView?.session.add(anchor: ARAnchor(name: Self.originName(space.id), transform: matrix_identity_float4x4))
            originWasAdded = true
        }
        resolvedAnchors = frame.anchors.reduce(into: [:]) { result, anchor in
            if let name = anchor.name { result[name] = anchor.transform }
        }
        let ready = normal && resolvedAnchors[Self.originName(space.id)] != nil
        guard ready else {
            suspendGuidance()
            if localizationStartedAt == nil { localizationStartedAt = frame.timestamp }
            if frame.timestamp - (localizationStartedAt ?? frame.timestamp) > 25 {
                mappingStatusText = "Room not recognized. Return to the saved entrance view or reload the space."
            }
            return
        }
        isLocalized = true
        localizationStartedAt = nil
        let hasAnchors = Self.requiredAnchorNames(for: space).allSatisfy { resolvedAnchors[$0] != nil }
        canSave = hasAnchors && pendingShelf == nil && (
            frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending
        )
        renderShelves()
        updateNavigation(frame: frame)
    }

    private func updateNavigation(frame: ARFrame) {
        guard let placement = targetPlacement else { return }
        let shelf = placement.shelf
        guard let targetTransform = resolvedAnchors[Self.shelfName(shelf.id)] else {
            guidance = nil
            navigationIssue = .shelfAnchor
            isAtShelf = false
            shelfScreenPosition = nil
            waypointVisual?.isEnabled = false
            routeStep = "Waiting for the saved shelf anchor"
            return
        }
        let stops = shelf.routeWaypoints.compactMap { resolvedAnchors[Self.waypointName($0.id)].map(Self.position) }
        guard stops.count == shelf.routeWaypoints.count else {
            guidance = nil
            navigationIssue = .aisleAnchors
            isAtShelf = false
            shelfScreenPosition = nil
            waypointVisual?.isEnabled = false
            routeStep = "Waiting for the saved aisle anchors"
            return
        }
        let shelfPosition = Self.position(targetTransform)
        if route == nil { route = ShelfRouteProgress(waypointPositions: stops, shelfPosition: shelfPosition) }
        guard route?.refreshPositions(waypointPositions: stops, shelfPosition: shelfPosition) == true else {
            guidance = nil
            navigationIssue = .aisleAnchors
            isAtShelf = false
            shelfScreenPosition = nil
            waypointVisual?.isEnabled = false
            return
        }
        route?.update(cameraPosition: Self.position(frame.camera.transform), isReady: isLocalized)
        guard let route else { return }
        isAtShelf = route.isAtShelf
        let activePoint = route.activeTargetPosition
        guidance = ShelfGuidance.calculate(cameraTransform: frame.camera.transform, targetPosition: activePoint, isReady: isLocalized)
        navigationIssue = guidance == nil ? .heading : nil
        if route.isAtShelf {
            routeStep = "\(shelf.label) · \(shelf.row) · \(placement.location.slotLabel)"
        } else if route.isFollowingWaypoints {
            routeStep = route.waypointIndex == 0 ? "Start at the recorded entrance" : "Aisle stop \(route.waypointIndex + 1) of \(stops.count)"
        } else { routeStep = "Approach \(shelf.label), \(shelf.row)" }
        updateWaypointVisual(at: activePoint, visible: route.isFollowingWaypoints)
        if let view = arView {
            let cameraSpace = frame.camera.transform.inverse * SIMD4(shelfPosition, 1)
            shelfScreenPosition = cameraSpace.z < 0 ? view.project(shelfPosition) : nil
        }
    }

    private func renderShelves() {
        guard let arView, let space else { return }
        for shelf in space.shelves {
            let shouldShow = isAdmin || targetPlacement?.shelf.id == shelf.id
            guard shouldShow, let transform = resolvedAnchors[Self.shelfName(shelf.id)] else {
                shelfVisuals[shelf.id]?.isEnabled = false
                continue
            }
            let visual: AnchorEntity
            if let existing = shelfVisuals[shelf.id] { visual = existing } else {
                visual = AnchorEntity(world: matrix_identity_float4x4)
                let material = UnlitMaterial(color: .systemCyan)
                let thickness: Float = 0.015
                for y in [-shelf.height / 2, shelf.height / 2] {
                    let edge = ModelEntity(mesh: .generateBox(size: [shelf.width, thickness, thickness]), materials: [material])
                    edge.position = [0, y, 0.025]
                    visual.addChild(edge)
                }
                for x in [-shelf.width / 2, shelf.width / 2] {
                    let edge = ModelEntity(mesh: .generateBox(size: [thickness, shelf.height, thickness]), materials: [material])
                    edge.position = [x, 0, 0.025]
                    visual.addChild(edge)
                }
                arView.scene.addAnchor(visual)
                shelfVisuals[shelf.id] = visual
            }
            visual.transform = Transform(matrix: transform)
            visual.isEnabled = isLocalized
        }
    }

    private func updateWaypointVisual(at point: SIMD3<Float>, visible: Bool) {
        guard let arView else { return }
        if waypointVisual == nil {
            let anchor = AnchorEntity(world: SIMD3<Float>.zero)
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [UnlitMaterial(color: .systemYellow)])
            anchor.addChild(dot)
            arView.scene.addAnchor(anchor)
            waypointVisual = anchor
        }
        waypointVisual?.position = point
        waypointVisual?.isEnabled = visible && isLocalized
    }

    private func removeVisuals() {
        shelfVisuals.values.forEach { $0.removeFromParent() }
        shelfVisuals = [:]
        waypointVisual?.removeFromParent()
        waypointVisual = nil
    }

    private func loadSavedData() {
        do {
            guard let saved = try readSavedData() else {
                clearSpaceData()
                return
            }
            applySavedData(saved)
        } catch {
            clearSpaceData()
            message = "Could not open the saved space: \(error.localizedDescription)"
        }
    }

    private func readSavedData() throws -> (data: SavedLibrarySpace, map: ARWorldMap)? {
        guard let saved = try store.load() else { return nil }
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: saved.worldMapData) else {
            throw SpaceError.invalidMap
        }
        try Self.validateAnchors(in: map, for: saved.space)
        return (saved, map)
    }

    private func applySavedData(_ saved: (data: SavedLibrarySpace, map: ARWorldMap)) {
        space = saved.data.space
        initialMap = saved.map
        isNewCoordinateSpace = false
        hasSavedSpace = true
        hasUnsavedChanges = false
        localizationImageData = saved.data.localizationImageData
        message = "Look around the saved entrance to recognize \(saved.data.space.name)."
    }

    private func clearSpaceData() {
        space = nil
        initialMap = nil
        hasSavedSpace = false
        hasUnsavedChanges = false
        isNewCoordinateSpace = false
        originWasAdded = false
        localizationImageData = nil
        mappingStatusText = "Look around the room"
    }

    private func imageData(from frame: ARFrame) -> Data? {
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = 600 / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.65)
    }

    private static func validateAnchors(in map: ARWorldMap, for space: LibrarySpace) throws {
        let names = map.anchors.compactMap(\.name)
        guard requiredAnchorNames(for: space).allSatisfy({ name in names.filter { $0 == name }.count == 1 }) else {
            throw SpaceError.missingAnchors
        }
    }

    private static func requiredAnchorNames(for space: LibrarySpace) -> [String] {
        [originName(space.id)] + space.shelves.flatMap {
            [shelfName($0.id)] + $0.routeWaypoints.map { waypointName($0.id) }
        }
    }

    private static func originName(_ id: UUID) -> String { "library-space:\(id.uuidString)" }
    private static func shelfName(_ id: UUID) -> String { "library-shelf:\(id.uuidString)" }
    private static func waypointName(_ id: UUID) -> String { "library-waypoint:\(id.uuidString)" }
    private static func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }
    private static func values(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
    }

    private enum SpaceError: LocalizedError {
        case invalidMap, missingAnchors
        var errorDescription: String? {
            switch self {
            case .invalidMap: return "This AR map cannot be read on this device."
            case .missingAnchors: return "Some shelf or aisle anchors are missing. Scan their area and save again."
            }
        }
    }
}

struct ShelfDraft {
    let label: String
    let row: String
    let width: Float
    let height: Float
    let instructions: String
}

enum ShelfNavigationIssue {
    case shelfAnchor
    case aisleAnchors
    case heading
}
