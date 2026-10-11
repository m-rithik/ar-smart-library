import SwiftUI
import UIKit

struct ScannerView: View {
    @StateObject private var controller = ARSessionController()
    @StateObject private var readingList = ReadingListStore()

    var body: some View {
        ScannerScene(controller: controller, spaceController: controller.librarySpace)
            .environmentObject(readingList)
    }
}

private struct ScannerScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var controller: ARSessionController
    @ObservedObject var spaceController: LibrarySpaceController
    @State private var showsLibrary = false
    @State private var confirmsRestart = false
    @State private var showsScanTips = false

    var body: some View {
        Group {
            if controller.isARSupported {
                cameraScene
            } else {
                LibrarySpacePanel(
                    controller: spaceController,
                    canUseAR: false,
                    arUnavailableReason: arUnavailableReason,
                    isRoot: true,
                    onFind: controller.startFinding,
                    onClose: {}
                )
            }
        }
        .tint(LibraryTheme.accent)
        .task {
            await controller.requestCameraAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await controller.requestCameraAccess()
                }
            } else {
                controller.pause()
            }
        }
        .sheet(isPresented: $showsLibrary) {
            LibrarySpacePanel(
                controller: spaceController,
                canUseAR: controller.canUseAR,
                arUnavailableReason: arUnavailableReason,
                onFind: controller.startFinding
            ) { showsLibrary = false }
        }
        .alert("Restart AR tracking?", isPresented: $confirmsRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart and discard changes", role: .destructive, action: controller.retryARSession)
        } message: {
            Text("Restarting reloads the last saved room. Unsaved shelf locations and the current route draft cannot be kept after tracking fails.")
        }
        .onDisappear {
            controller.pause()
        }
    }

    private var cameraScene: some View {
        GeometryReader { geometry in
            ZStack {
                LibraryTheme.background.ignoresSafeArea()
                ARViewContainer(controller: controller, viewportSize: geometry.size)

                LinearGradient(
                    colors: [.black.opacity(0.28), .clear, .clear, .black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                if
                    let point = controller.anchorScreenPosition,
                    let book = controller.selectedBook,
                    let policy = controller.scanPolicy,
                    CGRect(origin: .zero, size: geometry.size).contains(point)
                {
                    anchoredLabel(book: book, policy: policy)
                        .position(point)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.12), value: point)
                        .allowsHitTesting(false)
                }

                if let point = spaceController.shelfScreenPosition,
                   let placement = spaceController.targetPlacement,
                   CGRect(origin: .zero, size: geometry.size).contains(point) {
                    Label("\(placement.shelf.label) · \(placement.shelf.row)", systemImage: "books.vertical.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(10)
                        .background(.black.opacity(0.8), in: Capsule())
                        .foregroundStyle(LibraryTheme.accent)
                        .position(point)
                        .allowsHitTesting(false)
                }

                if controller.selectedBook == nil, controller.canUseAR,
                   spaceController.targetBook == nil,
                   !spaceController.isAdmin || spaceController.pendingShelf != nil {
                    reticle
                        .frame(
                            width: ScanTarget.size(in: geometry.size).width,
                            height: ScanTarget.size(in: geometry.size).height
                        )
                }

                VStack(spacing: 14) {
                    topBar

                    Spacer()

                    ScrollView {
                        VStack(spacing: 12) {
                            if dynamicTypeSize.isAccessibilitySize, controller.canUseAR {
                                Text(controller.statusMessage)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            }
                            bottomContent
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: geometry.size.height * trayHeightFraction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(LibraryTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(LibraryTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("AR SMART LIBRARY")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(LibraryTheme.textMuted)
                    }
                    Text(dynamicTypeSize.isAccessibilitySize ? "Scanner" : "Shelf scanner")
                        .font(.headline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Button { showsLibrary = true } label: {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(LibraryTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                }
                .accessibilityLabel("Open library search and admin setup")
                if controller.isLiDARAvailable {
                    Button(action: controller.toggleMeshVisualization) {
                        Image(systemName: controller.meshVisible ? "square.3.layers.3d.down.right.slash" : "square.3.layers.3d.down.right")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(LibraryTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel(controller.meshVisible ? "Hide LiDAR mesh" : "Show LiDAR mesh")
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
    
                Label("Local catalog · works offline", systemImage: "internaldrive")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LibraryTheme.accent)
                if controller.canUseAR {
                    Text(controller.statusMessage)
                        .font(.caption)
                        .foregroundStyle(LibraryTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(LibraryTheme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var trayHeightFraction: CGFloat {
        // Keep the center reticle and the next waypoint visible during spatial tasks.
        if controller.canUseAR, controller.selectedBook == nil { return 0.40 }
        return dynamicTypeSize.isAccessibilitySize ? 0.65 : 0.54
    }

    @ViewBuilder
    private var bottomContent: some View {
        if !controller.canUseAR {
            unavailableCard
        } else if spaceController.isBusyWithSpace {
            LibrarySpaceTaskCard(
                controller: spaceController,
                onOpenLibrary: { showsLibrary = true },
                onVerify: controller.verifyLocatedBook
            )
        } else if let comparison = controller.comparison {
            BookComparisonCard(
                comparison: comparison,
                onStartOver: controller.clearSelection
            )
        } else if
            let book = controller.selectedBook,
            let policy = controller.scanPolicy
        {
            BookDetailCard(
                book: book,
                confidence: controller.matchConfidence,
                policy: policy,
                recommendations: controller.recommendations,
                recommendationIntent: controller.recommendationIntent,
                allowsDiscoveryActions: true,
                onRecommendationIntentChange: controller.updateRecommendationIntent,
                onFind: controller.startFinding,
                onCompare: controller.startComparison,
                onScanAnother: controller.clearSelection
            )
        } else {
            VStack(spacing: 10) {
                Button { showsLibrary = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        Text("Browse the library")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(LibraryTheme.accent)
                .foregroundStyle(LibraryTheme.background)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                instructionCard
            }
        }
    }

    private var instructionCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: instructionIcon)
                    .font(.title2)
                    .foregroundStyle(LibraryTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(LibraryTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(instructionTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(instructionDetail)
                        .font(.caption)
                        .foregroundStyle(LibraryTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if isIdentifying {
                DisclosureGroup(isExpanded: $showsScanTips) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Fill the frame with one title or book spine.", systemImage: "viewfinder")
                        Label("Use even light and avoid glare on the cover.", systemImage: "sun.max")
                        Label("Hold still briefly so the title can be matched.", systemImage: "hand.raised")
                    }
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("Tips for a better scan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LibraryTheme.accent)
                        .frame(minHeight: 44)
                }
            } else {
                Button("Cancel task", action: controller.clearSelection)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var isIdentifying: Bool {
        if case .identify = controller.useCase {
            return true
        }
        return false
    }

    private var instructionIcon: String {
        switch controller.useCase {
        case .identify:
            return "text.viewfinder"
        case .find:
            return "scope"
        case .compare:
            return "rectangle.2.swap"
        }
    }

    private var instructionTitle: String {
        switch controller.useCase {
        case .identify:
            return "Align a title with the reticle"
        case let .find(target):
            return "Find \(target.title)"
        case let .compare(seed):
            return "Compare with \(seed.title)"
        }
    }

    private var instructionDetail: String {
        switch controller.useCase {
        case .identify:
            return "Hold steady while the app reads the title and measures its position in the room."
        case .find:
            return "Move across the shelf; the app will anchor the selected title when it appears."
        case .compare:
            return "Scan a different title to compare themes, genre, rating, and content overlap."
        }
    }

    private var arUnavailableReason: String? {
        if !controller.isARSupported { return "AR scanning and shelf directions need a compatible iPhone. The catalog is available here." }
        if controller.permissionDenied { return "Allow camera access in Settings to scan books and follow shelf directions." }
        if let error = controller.sessionFailureMessage { return "Tracking stopped: \(error)" }
        return nil
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: controller.permissionDenied ? "camera.fill" : "viewfinder")
                .font(.title2)
                .foregroundStyle(LibraryTheme.accent)
                .frame(width: 48, height: 48)
                .background(LibraryTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            Text(controller.sessionFailureMessage == nil ? "Library access" : "AR tracking stopped")
                .font(.title3.weight(.semibold))
            Text(arUnavailableReason ?? "AR is currently unavailable.")
                .font(.subheadline)
                .foregroundStyle(LibraryTheme.textMuted)
            Button { showsLibrary = true } label: {
                Label("Browse the library", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(LibraryTheme.accent)
            .foregroundStyle(LibraryTheme.background)
            if controller.permissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .frame(minHeight: 44)
                .buttonStyle(.bordered)
            } else if controller.sessionFailureMessage != nil {
                Button("Retry AR tracking") {
                    if spaceController.hasWorkingChanges { confirmsRestart = true }
                    else { controller.retryARSession() }
                }
                .frame(minHeight: 44)
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var reticle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)

            ScannerReticleCorners()
                .stroke(LibraryTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: 12, height: 12)

            VStack {
                Spacer()
                Text(spaceController.pendingShelf == nil ? "BOOK TITLE" : "SHELF CENTER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 8)
        .accessibilityHidden(true)
    }

    private func anchoredLabel(book: Book, policy: ScanPolicy) -> some View {
        Label(book.title, systemImage: policy.systemImage)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.78), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(policy == .exact ? Color.green : Color.orange, lineWidth: 1.5)
            }
    }

}

private struct ScannerReticleCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 24
        let radius: CGFloat = 18
        var path = Path()
        for corner in 0..<4 {
            let x = corner % 2 == 0 ? rect.minX : rect.maxX
            let y = corner < 2 ? rect.minY : rect.maxY
            let dx: CGFloat = corner % 2 == 0 ? 1 : -1
            let dy: CGFloat = corner < 2 ? 1 : -1
            path.move(to: CGPoint(x: x, y: y + dy * (radius + length)))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * (radius + length), y: y))
        }
        return path
    }
}
