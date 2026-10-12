import SwiftUI
import UIKit

struct LibrarySpacePanel: View {
    @ObservedObject var controller: LibrarySpaceController
    let canUseAR: Bool
    let arUnavailableReason: String?
    let onFind: (Book) -> Void
    let onClose: () -> Void
    let isRoot: Bool

    @State private var newSpaceName = ""
    @State private var shelfLabel = ""
    @State private var shelfRow = ""
    @State private var shelfWidth: Float = 0.9
    @State private var shelfHeight: Float = 0.3
    @State private var shelfInstructions = ""
    @State private var selectedBookID = ""
    @State private var selectedShelfID: UUID?
    @State private var slotLabel = ""
    @State private var initialShelfID: UUID?
    @State private var initialSlotLabel = ""
    @State private var assignmentExpanded = false
    @State private var assignmentScroll = 0
    @State private var assignmentFeedback: String?
    @State private var pendingAction: PanelAction?
    @State private var shelfToRemove: LibraryShelf?
    @State private var bookToRemove: Book?
    @State private var showsAddBook = false
    @State private var navigationPath: [Book] = []

    init(controller: LibrarySpaceController, canUseAR: Bool = true,
         arUnavailableReason: String? = nil, isRoot: Bool = false,
         onFind: @escaping (Book) -> Void, onClose: @escaping () -> Void) {
        self.controller = controller
        self.canUseAR = canUseAR
        self.arUnavailableReason = arUnavailableReason
        self.onFind = onFind
        self.onClose = onClose
        self.isRoot = isRoot
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { proxy in
                Group {
                    if controller.isAdmin {
                        Form {
                            modeSection
                            adminContent
                        }
                        .scrollContentBackground(.hidden)
                    } else {
                        CatalogBrowserView(controller: controller, canUseAR: canUseAR,
                                           onRetryAlignment: { request(.restore) })
                    }
                }
                .background(LibraryTheme.background)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assignmentScroll) { _, _ in proxy.scrollTo("assignment", anchor: .top) }
            }
            .navigationTitle(controller.isAdmin ? "Library setup" : "Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add book") { showsAddBook = true }
                        .disabled(controller.isSaving)
                }
                if !controller.isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { request(.mode(true)) } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Manage library and shelf locations")
                        .disabled(controller.isSaving)
                    }
                }
                if !isRoot {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { request(.close) } }
                }
            }
            .navigationDestination(for: Book.self) { book in
                CatalogBookDetailView(book: book, controller: controller, canUseAR: canUseAR,
                                      arUnavailableReason: arUnavailableReason, onFind: findBook)
            }
            .sheet(isPresented: $showsAddBook) {
                CustomBookForm(controller: controller) { book in
                    showsAddBook = false
                    navigationPath.append(book)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = controller.customBookError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(LibraryTheme.surface)
                }
            }
            .interactiveDismissDisabled(hasFormEdits)
            .alert(pendingAction?.title ?? "Discard changes?", isPresented: Binding(
                get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
            ), presenting: pendingAction) { action in
                Button("Keep editing", role: .cancel) { pendingAction = nil }
                Button("Discard and continue", role: .destructive) {
                    pendingAction = nil
                    perform(action)
                }
            } message: { action in Text(action.message) }
            .alert("Remove this shelf?", isPresented: Binding(
                get: { shelfToRemove != nil }, set: { if !$0 { shelfToRemove = nil } }
            )) {
                Button("Cancel", role: .cancel) { shelfToRemove = nil }
                Button("Remove", role: .destructive) {
                    if let shelf = shelfToRemove {
                        let affectsForm = selectedShelfID == shelf.id || initialShelfID == shelf.id
                        controller.removeShelf(id: shelf.id)
                        if affectsForm { loadAssignment(for: selectedBookID) }
                    }
                    shelfToRemove = nil
                }
            } message: {
                Text("This removes the shelf, its route and book assignments, including any unapplied form edits for this shelf. Save the space to keep the change.")
            }
            .alert("Remove this book location?", isPresented: Binding(
                get: { bookToRemove != nil }, set: { if !$0 { bookToRemove = nil } }
            )) {
                Button("Cancel", role: .cancel) { bookToRemove = nil }
                Button("Remove location", role: .destructive) {
                    if let book = bookToRemove {
                        controller.removeBookAssignment(bookID: book.id)
                        if selectedBookID == book.id { loadAssignment(for: book.id) }
                    }
                    bookToRemove = nil
                }
            } message: {
                Text("The book stays in the catalog. Its directions and any unapplied form edits for this book are removed; save to keep the change.")
            }
            .onAppear {
                if selectedBookID.isEmpty { loadAssignment(for: controller.catalog.first?.id ?? "") }
            }
            .onChange(of: controller.space?.shelves.map(\.id) ?? []) { _, _ in
                if !(controller.space?.shelves.contains { $0.id == selectedShelfID } ?? false) {
                    loadAssignment(for: selectedBookID)
                }
            }
        }
        .tint(LibraryTheme.accent)
    }

    private var modeSection: some View {
        Section {
            Picker("Library mode", selection: Binding(
                get: { controller.isAdmin }, set: { request(.mode($0)) }
            )) {
                Text("Reader").tag(false)
                Text("Admin").tag(true)
            }
            .pickerStyle(.segmented).disabled(controller.isSaving)
            if let space = controller.space {
                LabeledContent("Space", value: space.name)
                if controller.hasWorkingChanges {
                    Label("Changes are not saved", systemImage: "circle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                }
            }
        } footer: {
            if !canUseAR { Text("Browsing is available. AR scanning and directions are unavailable here.") }
        }
    }

    @ViewBuilder private var adminContent: some View {
        if controller.space == nil {
            Section {
                Text("Create the room, record routes to shelf rows, then assign each book a position.").font(.subheadline)
                Text(controller.message).font(.subheadline).foregroundStyle(.secondary)
                spaceNameField
                createButton
                if !canUseAR { Text(unavailableReason).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("1. Create your library space") } footer: {
                Text("Admin is a local setup mode. This iPhone stores one space; there is no account sign-in.")
            }
        } else {
            Section("1. Map the room") {
                RoomScanGuideView(controller: controller)
                Text(controller.message).font(.subheadline).foregroundStyle(.secondary)
                if !controller.isLocalized, let data = controller.localizationImageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Reference view of the library starting area")
                    Text("Return to this view and slowly look around with the camera.").font(.subheadline)
                }
                Button("Continue mapping in camera") { request(.close) }.disabled(!canUseAR)
                if let draft = controller.pendingShelf {
                    Text("Placement in progress: \(draft.label) · \(draft.row). \(controller.recordedStopCount) route stops recorded.")
                        .font(.subheadline)
                    Button("Continue placing shelf") { request(.close) }.disabled(!canUseAR)
                }
            }
            RoomLocationSection(controller: controller)
            Section("2. Shelf rows · \(controller.space?.shelves.count ?? 0)") {
                if controller.space?.shelves.isEmpty == true {
                    Text("Add a shelf row to mark where readers should look.").foregroundStyle(.secondary)
                }
                ForEach(controller.space?.shelves ?? []) { shelf in shelfContents(shelf) }
                DisclosureGroup("Add a shelf row") { shelfForm }
            }
            if controller.space?.shelves.isEmpty == false { assignmentSection.id("assignment") }
            saveSection
            Section {
                DisclosureGroup("Replace or restore the space") {
                    spaceNameField
                    createButton
                    if controller.hasSavedSpace { restoreButton }
                }
            } footer: {
                Text("This space is stored on this iPhone. Save changes before closing the app. Admin mode has no account access restriction.")
            }
        }
    }

    private var spaceNameField: some View { inputField("Library or room name", hint: "e.g. Main library", text: $newSpaceName) }
    private var createButton: some View {
        Button("Create AR space") { request(.createSpace) }
            .disabled(trimmed(newSpaceName).isEmpty || controller.isSaving || !canUseAR)
    }

    private func shelfContents(_ shelf: LibraryShelf) -> some View {
        DisclosureGroup {
            Text("\(shelf.routeWaypoints.count) recorded aisle stops").font(.subheadline).foregroundStyle(.secondary)
            if !shelf.instructions.isEmpty { Text(shelf.instructions).font(.subheadline) }
            let books = controller.catalog.filter { controller.space?.placement(for: $0.id)?.shelf.id == shelf.id }
            if books.isEmpty { Text("No books assigned. Add one under Book locations below.").font(.subheadline) }
            ForEach(books) { book in
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.subheadline.weight(.semibold))
                    Text(controller.space?.placement(for: book.id)?.location.slotLabel ?? "")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Menu("Manage location") {
                        Button("Edit location") { request(.selectBook(book.id)) }
                        Button("Remove location", role: .destructive) { bookToRemove = book }
                    }
                    .frame(minHeight: 44).disabled(controller.isSaving)
                }
            }
            Button("Remove shelf and assignments", role: .destructive) { shelfToRemove = shelf }
                .disabled(controller.isSaving)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(shelf.label) · \(shelf.row)").font(.headline)
                Text("\(controller.space?.bookLocations.filter { $0.shelfID == shelf.id }.count ?? 0) books assigned")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var shelfForm: some View {
        Group {
            inputField("Shelf label", hint: "e.g. A3", text: $shelfLabel)
            inputField("Row", hint: "e.g. second from top", text: $shelfRow)
            VStack(alignment: .leading) {
                Text("Row width: \(shelfWidth, specifier: "%.2f") m").font(.subheadline)
                Slider(value: $shelfWidth, in: 0.3...2.5, step: 0.05)
                    .accessibilityLabel("Shelf row width").accessibilityValue("\(shelfWidth, specifier: "%.2f") meters")
            }
            VStack(alignment: .leading) {
                Text("Row height: \(shelfHeight, specifier: "%.2f") m").font(.subheadline)
                Slider(value: $shelfHeight, in: 0.15...0.8, step: 0.05)
                    .accessibilityLabel("Shelf row height").accessibilityValue("\(shelfHeight, specifier: "%.2f") meters")
            }
            inputField("Directions or landmark (optional)", hint: "e.g. Next to the reading tables", text: $shelfInstructions)
            Text("Start at the entrance, record aisle stops along the route, then aim at the center of this row.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Record route and place shelf") { request(.placeShelf) }.disabled(shelfUnavailableReason != nil)
            if let reason = shelfUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var assignmentSection: some View {
        Section {
            DisclosureGroup("Assign or edit a book location", isExpanded: $assignmentExpanded) {
                Picker("Book", selection: Binding(get: { selectedBookID }, set: { request(.selectBook($0)) })) {
                    ForEach(controller.catalog) { Text($0.title).tag($0.id) }
                }
                Picker("Shelf row", selection: $selectedShelfID) {
                    Text("Choose a shelf").tag(UUID?.none)
                    ForEach(controller.space?.shelves ?? []) { Text("\($0.label) · \($0.row)").tag(Optional($0.id)) }
                }
                inputField("Book position", hint: "e.g. third from left", text: $slotLabel)
                if let current = controller.space?.placement(for: selectedBookID) {
                    Text("Current: \(current.shelf.label) · \(current.shelf.row) · \(current.location.slotLabel)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(controller.space?.placement(for: selectedBookID) == nil ? "Assign book location" : "Update book location") {
                    guard let shelfID = selectedShelfID else { return }
                    controller.assign(bookID: selectedBookID, shelfID: shelfID, slotLabel: trimmed(slotLabel))
                    assignmentFeedback = controller.message
                    if let placement = controller.space?.placement(for: selectedBookID),
                       placement.shelf.id == shelfID, placement.location.slotLabel == trimmed(slotLabel) {
                        initialShelfID = selectedShelfID
                        initialSlotLabel = trimmed(slotLabel)
                    }
                }
                .disabled(selectedBookID.isEmpty || selectedShelfID == nil || trimmed(slotLabel).isEmpty || controller.isSaving)
                if let assignmentFeedback { Label(assignmentFeedback, systemImage: "info.circle").font(.subheadline) }
                if hasAssignmentEdits {
                    Button("Discard form edits") { loadAssignment(for: selectedBookID) }
                } else if trimmed(slotLabel).isEmpty {
                    Text("Enter a position so readers know where to look within the row.").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: { Text("3. Book locations") } footer: {
            Text("The AR outline marks the row. The position locates the book within it; scanning the title confirms the book.")
        }
    }

    private var saveSection: some View {
        Section {
            Button(action: controller.saveSpace) {
                HStack {
                    Label(controller.isSaving ? "Saving AR space…" : "Save AR space", systemImage: "square.and.arrow.down")
                    Spacer()
                    if controller.isSaving { ProgressView() }
                }
            }
            .disabled(!canUseAR || !controller.canSave || controller.isSaving || hasAssignmentEdits)
            if hasAssignmentEdits {
                Text("Apply or discard the book location form before saving.").font(.subheadline)
            } else if !canUseAR {
                Text(unavailableReason).font(.subheadline)
            } else if controller.pendingShelf != nil {
                Text("Finish or cancel the current shelf placement before saving.").font(.subheadline)
            } else if !controller.canSave {
                Text(controller.mappingStatusText).font(.subheadline)
            }
            Text(controller.message).font(.subheadline).foregroundStyle(.secondary)
        } header: { Text("4. Save for readers") } footer: {
            Text("Saving keeps the room map, routes and assignments together for future sessions.")
        }
    }

    private var restoreButton: some View {
        Group {
            Button("Restore saved space") { request(.restore) }.disabled(controller.isSaving || !canUseAR)
            Text(controller.message).font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func inputField(_ title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline)
            TextField(hint, text: text, axis: .vertical).accessibilityLabel(title)
        }
    }
    private var unavailableReason: String { arUnavailableReason ?? "AR needs an available camera and a supported iPhone." }
    private var shelfUnavailableReason: String? {
        if !canUseAR { return unavailableReason }
        if controller.isSaving { return "Wait for the current save to finish." }
        if trimmed(shelfLabel).isEmpty || trimmed(shelfRow).isEmpty { return "Enter a shelf label and row." }
        if !controller.isLocalized { return "Return to the camera and align the room before recording a route." }
        return nil
    }
    private var hasAssignmentEdits: Bool { selectedShelfID != initialShelfID || trimmed(slotLabel) != initialSlotLabel }
    private var hasFormEdits: Bool {
        hasAssignmentEdits || !trimmed(newSpaceName).isEmpty || !trimmed(shelfLabel).isEmpty
            || !trimmed(shelfRow).isEmpty || !trimmed(shelfInstructions).isEmpty
            || shelfWidth != 0.9 || shelfHeight != 0.3
    }
    private func findBook(_ book: Book) {
        guard canUseAR, !controller.isSaving else { return }
        request(.find(book))
    }
    private func loadAssignment(for bookID: String) {
        selectedBookID = bookID
        let placement = controller.space?.placement(for: bookID)
        selectedShelfID = placement?.shelf.id ?? controller.space?.shelves.first?.id
        slotLabel = placement?.location.slotLabel ?? ""
        initialShelfID = selectedShelfID
        initialSlotLabel = slotLabel
        assignmentFeedback = nil
    }
    private func request(_ action: PanelAction) {
        if case let .mode(value) = action, value == controller.isAdmin { return }
        let confirm: Bool
        switch action {
        case .createSpace: confirm = controller.space != nil || hasAssignmentEdits
        case .restore: confirm = controller.hasWorkingChanges || hasFormEdits
        case .mode, .placeShelf: confirm = controller.pendingShelf != nil || hasAssignmentEdits
        case .close, .find: confirm = hasFormEdits
        case .selectBook: confirm = hasAssignmentEdits
        }
        if confirm { pendingAction = action } else { perform(action) }
    }
    private func perform(_ action: PanelAction) {
        switch action {
        case .close: onClose()
        case let .find(book):
            guard canUseAR, !controller.isSaving else { return }
            onFind(book)
            onClose()
        case let .mode(isAdmin):
            controller.cancelShelfPlacement()
            loadAssignment(for: selectedBookID)
            controller.setAdminMode(isAdmin)
        case let .selectBook(bookID):
            loadAssignment(for: bookID)
            assignmentExpanded = true
            assignmentScroll += 1
        case .createSpace:
            guard canUseAR, !controller.isSaving else { return }
            controller.beginNewSpace(name: trimmed(newSpaceName))
            onClose()
        case .restore:
            if controller.restoreSavedSpace() { onClose() }
        case .placeShelf:
            guard shelfUnavailableReason == nil else { return }
            controller.cancelShelfPlacement()
            controller.beginPlacingShelf(label: trimmed(shelfLabel), row: trimmed(shelfRow),
                width: shelfWidth, height: shelfHeight, instructions: trimmed(shelfInstructions))
            if controller.pendingShelf != nil { onClose() }
        }
    }
    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private enum PanelAction {
    case close, find(Book), mode(Bool), selectBook(String), createSpace, restore, placeShelf
    var title: String {
        switch self {
        case .createSpace: return "Start a new AR space?"
        case .restore: return "Restore the saved space?"
        case .mode, .placeShelf: return "Discard the unfinished setup?"
        case .close, .find: return "Discard unsubmitted form edits?"
        case .selectBook: return "Discard the book location form?"
        }
    }
    var message: String {
        switch self {
        case .createSpace:
            return "The working space, unfinished route and unsaved edits will be replaced. The last saved space stays available until a new save succeeds."
        case .restore:
            return "The working space, unfinished route and unsaved edits will be replaced by the last saved space."
        case .mode, .placeShelf:
            return "The unfinished shelf route and unapplied book location form will be discarded. Existing shelves and applied assignments stay in the working space."
        case .close, .find:
            return "Unsubmitted room, shelf and book location details will be discarded. Applied changes and any recorded route stay in the working space."
        case .selectBook:
            return "Your book location form edits have not been applied. The existing assignment will stay unchanged."
        }
    }
}
