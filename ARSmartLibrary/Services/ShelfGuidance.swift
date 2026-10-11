import Foundation
import simd

/// A direct bearing to a mapped shelf, not a route around obstacles.
struct ShelfGuidance: Equatable {
    enum Bearing: Equatable {
        case ahead
        case left
        case right
        case behind
    }

    enum VerticalHint: Equatable {
        case above
        case level
        case below
    }

    let distance: Float
    let horizontalDistance: Float
    /// Positive angles turn right; negative angles turn left.
    let bearingDegrees: Float
    let bearing: Bearing
    /// Height relative to the camera, in meters.
    let heightDifference: Float
    let verticalHint: VerticalHint
    let arrived: Bool

    var instruction: String {
        let turn: String
        switch bearing {
        case .ahead:
            turn = ""
        case .left:
            turn = "Turn left \(Int(abs(bearingDegrees).rounded()))°. "
        case .right:
            turn = "Turn right \(Int(abs(bearingDegrees).rounded()))°. "
        case .behind:
            turn = "Turn around. "
        }

        if arrived {
            switch verticalHint {
            case .above:
                return "At the shelf. \(turn)Look \(meters(abs(heightDifference))) above the phone."
            case .below:
                return "At the shelf. \(turn)Look \(meters(abs(heightDifference))) below the phone."
            case .level:
                return "At the shelf. \(turn)Look at phone height."
            }
        }

        return "\(turn)Shelf is \(meters(horizontalDistance)) \(bearing == .ahead ? "ahead" : "away")."
    }

    static func calculate(
        cameraTransform: simd_float4x4,
        targetPosition: SIMD3<Float>,
        isReady: Bool
    ) -> ShelfGuidance? {
        guard isReady,
              (0..<4).allSatisfy({ column in
                  (0..<4).allSatisfy { cameraTransform[column][$0].isFinite }
              }),
              (0..<3).allSatisfy({ targetPosition[$0].isFinite }) else {
            return nil
        }

        let translation = cameraTransform.columns.3
        let displacement = targetPosition - SIMD3(translation.x, translation.y, translation.z)
        let horizontalDisplacement = SIMD2(displacement.x, displacement.z)
        let horizontalDistance = simd_length(horizontalDisplacement)
        let distance = simd_length(displacement)
        let projectedForward = SIMD2(-cameraTransform.columns.2.x, -cameraTransform.columns.2.z)
        let forwardLength = simd_length(projectedForward)

        // A camera aimed straight up or down has no reliable horizontal bearing.
        guard horizontalDistance.isFinite, distance.isFinite,
              forwardLength.isFinite, forwardLength > 0.001 else {
            return nil
        }

        let forward = projectedForward / forwardLength
        let right = SIMD2(-forward.y, forward.x)
        let bearingDegrees: Float
        if horizontalDistance < 0.001 {
            bearingDegrees = 0
        } else {
            bearingDegrees = atan2(
                simd_dot(horizontalDisplacement, right),
                simd_dot(horizontalDisplacement, forward)
            ) * 180 / .pi
        }

        let bearing: Bearing
        if abs(bearingDegrees) <= 20 {
            bearing = .ahead
        } else if abs(bearingDegrees) >= 160 {
            bearing = .behind
        } else {
            bearing = bearingDegrees < 0 ? .left : .right
        }

        let verticalHint: VerticalHint
        if displacement.y > 0.25 {
            verticalHint = .above
        } else if displacement.y < -0.25 {
            verticalHint = .below
        } else {
            verticalHint = .level
        }

        return ShelfGuidance(
            distance: distance,
            horizontalDistance: horizontalDistance,
            bearingDegrees: bearingDegrees,
            bearing: bearing,
            heightDifference: displacement.y,
            verticalHint: verticalHint,
            arrived: horizontalDistance <= 0.8
        )
    }

    private func meters(_ value: Float) -> String {
        String(format: "%.1f m", value)
    }
}

/// Follows administrator-placed checkpoints in order before targeting the shelf.
struct ShelfRouteProgress {
    private(set) var waypointPositions: [SIMD3<Float>]
    private(set) var shelfPosition: SIMD3<Float>
    private(set) var waypointIndex = 0
    private(set) var isAtShelf = false

    var isFollowingWaypoints: Bool {
        waypointIndex < waypointPositions.count
    }

    var activeTargetPosition: SIMD3<Float> {
        isFollowingWaypoints ? waypointPositions[waypointIndex] : shelfPosition
    }

    /// Refreshes restored AR anchors while preserving completed checkpoints.
    /// Evaluate arrival again with `update` after refreshing the positions.
    @discardableResult
    mutating func refreshPositions(
        waypointPositions: [SIMD3<Float>],
        shelfPosition: SIMD3<Float>
    ) -> Bool {
        guard waypointPositions.count == self.waypointPositions.count,
              waypointPositions.allSatisfy(Self.isFinite), Self.isFinite(shelfPosition) else {
            return false
        }

        self.waypointPositions = waypointPositions
        self.shelfPosition = shelfPosition
        isAtShelf = false
        return true
    }

    mutating func update(cameraPosition: SIMD3<Float>, isReady: Bool) {
        isAtShelf = false
        guard isReady,
              Self.isFinite(cameraPosition), Self.isFinite(shelfPosition),
              waypointPositions.allSatisfy(Self.isFinite) else {
            return
        }

        let displacement = activeTargetPosition - cameraPosition
        let distance = simd_length(SIMD2(displacement.x, displacement.z))
        guard distance.isFinite else { return }

        if isFollowingWaypoints {
            if distance <= 0.65 {
                waypointIndex += 1
            }
            return
        }

        isAtShelf = distance <= 0.8
    }

    mutating func reset() {
        waypointIndex = 0
        isAtShelf = false
    }

    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        (0..<3).allSatisfy { point[$0].isFinite }
    }
}
