import SwiftUI
import UIKit

struct LibrarySpaceTaskCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmsCancellation = false

    @ObservedObject var controller: LibrarySpaceController
    let onOpenLibrary: () -> Void
    let onVerify: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let draft = controller.pendingShelf {
                Label("Place \(draft.label) · \(draft.row)", systemImage: "square.dashed")
                    .font(.headline)
                Text("Start at the entrance and record a stop. Walk the route, recording stops at aisle turns. Face the shelf straight-on and aim the reticle at the row center to place its outline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                adaptiveLayout {
                    Button(action: controller.recordRouteStop) {
                        Text("Record stop (\(controller.recordedStopCount))")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.isLocalized)
                    Button(action: controller.undoRouteStop) {
                        Label("Undo stop", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: 44)
                    }
                    .disabled(controller.recordedStopCount == 0)
                }
                Button(action: controller.placeShelfAtReticle) {
                    Text("Place shelf row here").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.isLocalized || controller.recordedStopCount == 0)
                Button { confirmsCancellation = true } label: {
                    Text("Cancel placement").frame(minHeight: 44)
                }
                .font(.subheadline)
            } else if let book = controller.targetBook {
                Text(book.title).font(.headline)
                if let placement = controller.targetPlacement {
                    Text("\(placement.shelf.label) · \(placement.shelf.row) · \(placement.location.slotLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    if !placement.shelf.instructions.isEmpty {
                        Text(placement.shelf.instructions).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if controller.isLocalized, let guidance = controller.guidance {
                    adaptiveLayout {
                        if controller.isAtShelf {
                            Image(systemName: "scope")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.cyan)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.routeStep).font(.subheadline.weight(.semibold))
                            if controller.isAtShelf {
                                Text(guidance.instruction).font(.caption)
                            } else {
                                Text("\(guidance.horizontalDistance, specifier: "%.1f") m to next stop · \(turnText(guidance))")
                                    .font(.caption)
                            }
                        }
                    }
                    if controller.isAtShelf {
                        Text("The cyan outline marks the assigned row. Check the slot label and scan the title to confirm the actual book.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { onVerify(book) } label: {
                            Text("Scan title to confirm").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Follow the recorded aisle stops. Keep the walkway in view and use only clear aisles; this route does not detect obstacles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !controller.isLocalized {
                    Label("Recognizing the saved room", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                    Text(controller.mappingStatusText).font(.caption).foregroundStyle(.secondary)
                    if let data = controller.localizationImageData, let image = UIImage(data: data) {
                        adaptiveLayout {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 90, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Saved entrance reference photo")
                            Text("Return to this entrance view and slowly look around. Directions appear when the room aligns.")
                                .font(.caption)
                        }
                    }
                    retryAlignmentButton
                } else if controller.navigationIssue == .shelfAnchor || controller.navigationIssue == .aisleAnchors {
                    Label("Locating the recorded route", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                    Text(controller.routeStep).font(.caption)
                    Text("The room is aligned, but the saved shelf or aisle positions are not available yet. Slowly scan the surrounding shelves before walking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    retryAlignmentButton
                } else {
                    Label("Hold your iPhone upright", systemImage: "iphone")
                        .font(.subheadline.weight(.semibold))
                    Text("Point the camera ahead, not straight at the floor or ceiling, so the app can determine which way to guide you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: controller.cancelNavigation) {
                    Text("End directions").frame(minHeight: 44)
                }
                .font(.subheadline)
            } else {
                Label(controller.space?.name ?? "Set up the library", systemImage: "arkit")
                    .font(.headline)
                Text(controller.mappingStatusText).font(.subheadline)
                Button(action: onOpenLibrary) {
                    Text("Manage shelves and book locations").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                if controller.canSave {
                    Button(action: controller.saveSpace) {
                        Text(controller.isSaving ? "Saving…" : "Save AR space").frame(minHeight: 44)
                    }
                    .disabled(controller.isSaving)
                }
            }
            if !controller.message.isEmpty {
                Text(controller.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog("Discard this shelf placement?", isPresented: $confirmsCancellation, titleVisibility: .visible) {
            Button("Discard placement", role: .destructive, action: controller.cancelShelfPlacement)
            Button("Keep placing", role: .cancel) { }
        } message: {
            Text("The shelf details and \(controller.recordedStopCount) recorded route stops will be discarded. Existing shelves will not change.")
        }
    }

    private var adaptiveLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    @ViewBuilder
    private var retryAlignmentButton: some View {
        if controller.hasSavedSpace {
            Button { controller.restoreSavedSpace() } label: {
                Text("Retry room alignment").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(controller.hasWorkingChanges || controller.isSaving)
            if controller.hasWorkingChanges {
                Text("Save or discard your working changes in Admin before reloading the saved room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func turnText(_ guidance: ShelfGuidance) -> String {
        switch guidance.bearing {
        case .ahead: return "straight ahead"
        case .behind: return "turn around"
        case .left: return "turn left"
        case .right: return "turn right"
        }
    }
}
