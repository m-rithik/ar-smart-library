import SwiftUI

struct CatalogBookDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let book: Book
    @ObservedObject var controller: LibrarySpaceController
    let canUseAR: Bool
    let arUnavailableReason: String?
    let onFind: (Book) -> Void
    @State private var intent: RecommendationIntent = .similar

    private var placement: LibraryBookPlacement? { controller.space?.placement(for: book.id) }
    private var recommendations: [BookRecommendation] {
        RecommendationEngine().recommendations(for: book, from: controller.catalog, intent: intent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                bookHero
                aboutSection
                locationSection
                relatedSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryTheme.background)
        .tint(LibraryTheme.accent)
        .navigationTitle("Book details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bookHero: some View {
        VStack(spacing: 20) {
            BookCoverView(book: book, width: 154)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background {
                    Circle()
                        .fill(LibraryTheme.accent.opacity(0.09))
                        .frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                }

            VStack(spacing: 8) {
                Text(book.genre.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(LibraryTheme.accent)
                Text(book.title)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("by \(book.author)")
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textMuted)
            }
            .frame(maxWidth: .infinity)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    ratingLabel
                    Divider().frame(height: 18)
                    placementLabel
                }
                VStack(spacing: 8) {
                    ratingLabel
                    placementLabel
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(LibraryTheme.textMuted)

            ReadingStatusMenu(book: book)
                .frame(maxWidth: .infinity)
        }
    }

    private var ratingLabel: some View {
        Label("\(book.rating.formatted(.number.precision(.fractionLength(1)))) / 5 · demo rating", systemImage: "star.fill")
    }

    private var placementLabel: some View {
        Label(placement == nil ? "Location unassigned" : "Shelf location assigned", systemImage: "books.vertical")
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Between the covers", subtitle: "About this book")
            Text(book.summary)
                .font(.body)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !book.keywords.isEmpty {
                Text("EXPLORE THE THEMES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .padding(.top, 2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 115), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(book.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(LibraryTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Text("Ratings are from the bundled demo catalog, not live reviews.")
                .font(.caption)
                .foregroundStyle(LibraryTheme.textMuted)
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.north.circle.fill")
                    .font(.title)
                    .foregroundStyle(LibraryTheme.accent)
                    .accessibilityHidden(true)
                sectionHeading("Find your next read", subtitle: "In the library")
            }

            if let placement {
                VStack(spacing: 12) {
                    LabeledContent("Shelf", value: placement.shelf.label)
                    LabeledContent("Row", value: placement.shelf.row)
                    LabeledContent("Position", value: placement.location.slotLabel)
                }
                .font(.subheadline)
                if !placement.shelf.instructions.isEmpty {
                    Label(placement.shelf.instructions, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(LibraryTheme.textMuted)
                }
            } else {
                Text("This book is waiting for a shelf location.")
                    .font(.subheadline.weight(.semibold))
                Text("Scan the shelves for its title. An admin can add a location to enable directions.")
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textMuted)
            }

            Button { onFind(book) } label: {
                Label(placement == nil ? "Scan for this title" : "Take me to this book",
                      systemImage: placement == nil ? "text.viewfinder" : "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(LibraryTheme.background)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(!canUseAR || controller.isSaving)

            if !canUseAR {
                Label(arUnavailableReason ?? "AR needs an available camera and a supported iPhone.", systemImage: "camera")
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
            } else if controller.isSaving {
                Text("Wait for the library save to finish before starting directions.")
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
            }
            if placement != nil {
                Text("Follow the recorded aisle route, then scan the title to confirm the book is still at its assigned location.")
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
            }
        }
        .padding(20)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Keep the story going", subtitle: "Related books")
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Discover", selection: $intent) {
                    ForEach(RecommendationIntent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Discover", selection: $intent) {
                    ForEach(RecommendationIntent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if recommendations.isEmpty {
                Label("No related books were found in this catalog.", systemImage: "books.vertical")
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .padding(.vertical, 14)
            }
            ForEach(recommendations) { recommendation in
                NavigationLink(value: recommendation.book) {
                    relatedBook(recommendation)
                }
                .buttonStyle(.plain)
            }
            Text("Suggestions use the books’ themes, descriptions and demo catalog ratings.")
                .font(.caption)
                .foregroundStyle(LibraryTheme.textMuted)
        }
    }

    private func relatedBook(_ recommendation: BookRecommendation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                BookCoverView(book: recommendation.book, width: 60)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(recommendation.book.title)
                    .font(.headline)
                Text(recommendation.book.author)
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(LibraryTheme.textMuted)
                .padding(.top, 5)
                .accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(LibraryTheme.textMuted)
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }
}
