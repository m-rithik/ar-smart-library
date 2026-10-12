import ARKit

struct RoomScanGuidance: Equatable {
    enum Status: Equatable {
        case unavailable
        case initializing
        case excessiveMotion
        case insufficientFeatures
        case relocalizing
        case relocalizationDelayed
        case locatingOrigin
        case restoringAnchors
        case mappingUnavailable
        case mappingLimited
        case mappingExtending
        case visibleAreaMapped
    }

    let status: Status
    let title: String
    let instruction: String
    let symbol: String

    static func evaluate(
        trackingState: ARCamera.TrackingState,
        mappingStatus: ARFrame.WorldMappingStatus,
        originRecognized: Bool,
        allAnchorsAvailable: Bool,
        isNewSpace: Bool,
        shelfCount: Int,
        relocalizationTimedOut: Bool = false
    ) -> RoomScanGuidance {
        let isRelocalizing: Bool
        switch trackingState {
        case .notAvailable:
            return RoomScanGuidance(
                status: .unavailable, title: "Camera tracking unavailable",
                instruction: "Keep the camera uncovered and return to the live camera view. Wait for tracking before recording a stop or shelf.",
                symbol: "camera"
            )
        case .limited(.initializing):
            return RoomScanGuidance(
                status: .initializing, title: "Start with a clear view",
                instruction: isNewSpace
                    ? "Stand at the entrance. Point at shelf fronts or a room corner and slowly move the phone a little from side to side."
                    : "Return to the saved entrance view. Point at the same shelves and corners, then slowly move the phone from side to side.",
                symbol: "viewfinder"
            )
        case .limited(.excessiveMotion):
            return RoomScanGuidance(
                status: .excessiveMotion, title: "Slow down",
                instruction: "Pause walking and steady the phone. Then sweep slowly across the shelves; avoid quick turns.",
                symbol: "hand.raised"
            )
        case .limited(.insufficientFeatures):
            return RoomScanGuidance(
                status: .insufficientFeatures, title: "Find more visual detail",
                instruction: "Point at book spines, shelf edges, or a room corner. Move away from blank walls, glare, and dark areas.",
                symbol: "text.viewfinder"
            )
        case .limited(.relocalizing):
            isRelocalizing = true
        case .normal:
            isRelocalizing = false
        case .limited:
            return RoomScanGuidance(
                status: .unavailable, title: "Tracking needs a clearer view",
                instruction: "Steady the phone and slowly scan nearby shelves and corners before continuing.",
                symbol: "viewfinder"
            )
        }

        if isRelocalizing || (!isNewSpace && !originRecognized) {
            return RoomScanGuidance(
                status: relocalizationTimedOut ? .relocalizationDelayed : .relocalizing,
                title: relocalizationTimedOut ? "Return to the starting view" : "Recognizing the room",
                instruction: isNewSpace
                    ? "Return to where you began this scan. Hold the phone at a similar height and slowly look across the same shelves and corners."
                    : relocalizationTimedOut
                        ? "Return to the saved starting view at the same phone height and direction. Match the entrance photo if one is shown, then slowly scan nearby shelves."
                        : "Match the saved entrance view, including the phone height and direction. Slowly look across the same shelves and corners.",
                symbol: "viewfinder"
            )
        }

        guard originRecognized else {
            return RoomScanGuidance(
                status: .locatingOrigin, title: "Establishing the starting area",
                instruction: "Stay near the entrance and slowly scan shelf fronts and room corners until the starting area is ready.",
                symbol: "location.viewfinder"
            )
        }

        guard allAnchorsAvailable else {
            return RoomScanGuidance(
                status: .restoringAnchors, title: "Locate the recorded shelves",
                instruction: "The starting area is aligned. Slowly scan the recorded shelf rows and aisle turns so their saved positions can be found before saving or following directions.",
                symbol: "books.vertical"
            )
        }

        switch mappingStatus {
        case .notAvailable:
            return RoomScanGuidance(
                status: .mappingUnavailable, title: "Build the room map",
                instruction: "Slowly scan the entrance, shelf fronts, and room corners. Move a little sideways so the camera sees their depth.",
                symbol: "viewfinder"
            )
        case .limited:
            return RoomScanGuidance(
                status: .mappingLimited, title: "Scan more of the nearby area",
                instruction: "Sweep across shelf edges, book spines, and corners. Take a small step sideways and view the same details from another angle.",
                symbol: "viewfinder"
            )
        case .extending:
            return RoomScanGuidance(
                status: .mappingExtending, title: "Mapping the next area",
                instruction: shelfCount == 0
                    ? "The scan has enough detail to save. Add a shelf row next, then record the entrance and aisle turns on the way to it."
                    : "The scan has enough detail to save after finishing your shelf work. For stronger alignment later, revisit the entrance and slowly scan each shelf row from another angle.",
                symbol: "square.3.layers.3d"
            )
        case .mapped:
            return RoomScanGuidance(
                status: .visibleAreaMapped, title: "Visible area mapped",
                instruction: shelfCount == 0
                    ? "Add a shelf row next. Record the entrance first, then stops at aisle turns as you walk to the shelf."
                    : "Check each shelf outline and recorded route. Finish any shelf placement and save the AR space; scan more areas if you still need to add shelves.",
                symbol: "checkmark.circle"
            )
        @unknown default:
            return RoomScanGuidance(
                status: .mappingLimited, title: "Keep scanning the nearby area",
                instruction: "Move slowly and scan detailed shelves and room corners before saving.",
                symbol: "viewfinder"
            )
        }
    }
}
