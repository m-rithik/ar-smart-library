import SwiftUI

struct RoomScanGuideView: View {
    @ObservedObject var controller: LibrarySpaceController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(controller.roomScanGuidance.title, systemImage: controller.roomScanGuidance.symbol)
                .font(.headline)
            Text(controller.roomScanGuidance.instruction)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Label(controller.isLocalized ? "Camera + motion tracking aligned" : "Camera + motion tracking aligning",
                  systemImage: controller.isLocalized ? "checkmark.circle" : "viewfinder")
                .font(.caption).foregroundStyle(.secondary)
            if controller.hasLiveDepth {
                Label("LiDAR is measuring surfaces", systemImage: "square.3.layers.3d")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Entrance → aisle turns → shelf fronts → save")
                .font(.caption.weight(.medium))
        }
    }
}
