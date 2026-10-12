import SwiftUI

struct RoomLocationSection: View {
    @ObservedObject var controller: LibrarySpaceController
    @StateObject private var location = RoomLocationService()

    var body: some View {
        Section {
            if let tag = controller.space?.roomGeotag {
                Label("Room location added", systemImage: "mappin.circle.fill")
                Text("Accuracy: about \(Int(tag.horizontalAccuracy.rounded())) m")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(controller.space?.roomGeotag == nil ? "Add room location" : "Update room location") {
                guard let spaceID = controller.space?.id else { return }
                location.onCaptured = { [weak controller] tag in
                    controller?.setRoomGeotag(tag, for: spaceID)
                }
                location.requestLocation()
            }
            .disabled(location.isRequesting || controller.isSaving)
            if location.isRequesting {
                ProgressView("Finding room location…")
                Button("Cancel location request", action: location.cancel)
            }
            Text(location.message).font(.caption).foregroundStyle(.secondary)
            if controller.space?.roomGeotag != nil {
                Button("Remove room location", role: .destructive) {
                    location.cancel()
                    if let spaceID = controller.space?.id { controller.setRoomGeotag(nil, for: spaceID) }
                }
                .disabled(controller.isSaving)
            }
        } header: {
            Text("Room location · optional")
        } footer: {
            Text("Stored on this iPhone when you save the AR space. This tags the building area; the camera and motion sensors locate shelves. Scanning works without location access.")
        }
        .onChange(of: controller.space?.id) { _, _ in location.cancel() }
        .onChange(of: controller.isSaving) { _, saving in if saving { location.cancel() } }
        .onDisappear { location.cancel() }
    }
}
