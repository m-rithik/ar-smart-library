import SwiftUI

struct BookDetailCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsFullSummary = false

    let book: Book
    let confidence: Double
    let policy: ScanPolicy
    let recommendations: [BookRecommendation]
    let recommendationIntent: RecommendationIntent
    let allowsDiscoveryActions: Bool
    let onRecommendationIntentChange: (RecommendationIntent) -> Void
    let onFind: (Book) -> Void
    let onCompare: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            adaptiveLayout(spacing: 10).callAsFunction {
                Label("ON YOUR SHELF", systemImage: "sparkle.viewfinder")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                policyBadge
            }

            adaptiveLayout(spacing: 16).callAsFunction {
                BookCoverView(book: book, width: 76)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(LibraryTheme.textMuted)
                    Text(book.genre)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LibraryTheme.accent)
                    Label("\(book.rating.formatted(.number.precision(.fractionLength(1)))) / 5 · demo rating", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(LibraryTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("\(confidence.formatted(.percent.precision(.fractionLength(0)))) title match score", systemImage: "text.viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LibraryTheme.textMuted)
                ProgressView(value: confidence)
                    .tint(policyColor)
                    .accessibilityHidden(true)
            }

            ReadingStatusMenu(book: book)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.summary)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .lineLimit(showsFullSummary ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsFullSummary.toggle() }
                } label: {
                    Label(showsFullSummary ? "Show less" : "Read full summary", systemImage: showsFullSummary ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityValue(showsFullSummary ? "Expanded" : "Collapsed")
            }

            Divider()
            relatedBooks

            adaptiveLayout(spacing: 10).callAsFunction {
                if allowsDiscoveryActions {
                    Button(action: onCompare) {
                        Label("Compare", systemImage: "rectangle.2.swap")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: onScanAnother) {
                    Label("Scan another", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            .foregroundStyle(LibraryTheme.background)
            }
            .font(.subheadline.weight(.semibold))
            .buttonBorderShape(.roundedRectangle(radius: 12))
        }
        .padding(20)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .tint(LibraryTheme.accent)
        .onChange(of: book.id) { showsFullSummary = false }
    }

    private var relatedBooks: some View {
        VStack(alignment: .leading, spacing: 12) {
            adaptiveLayout(spacing: 8).callAsFunction {
                Text("Your next discovery")
                    .font(.system(.headline, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    ForEach(RecommendationIntent.allCases) { intent in
                        Button {
                            onRecommendationIntentChange(intent)
                        } label: {
                            if intent == recommendationIntent {
                                Label(intent.title, systemImage: "checkmark")
                            } else {
                                Text(intent.title)
                            }
                        }
                    }
                } label: {
                    Label(recommendationIntent.title, systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Related books: \(recommendationIntent.title)")
            }

            if recommendations.isEmpty {
                Text("No related books were found in this catalog. Try scanning a different book.")
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textMuted)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(recommendations) { recommendation in
                        recommendationCard(recommendation)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(recommendations) { recommendation in
                            recommendationCard(recommendation)
                                .frame(width: 250)
                        }
                    }
                }
            }
            Text("Suggestions use catalog themes and descriptions. Ratings are demo data.")
                .font(.caption2)
                .foregroundStyle(LibraryTheme.textMuted)
        }
    }

    private func adaptiveLayout(spacing: CGFloat) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
    }

    private var policyBadge: some View {
        Label(policy.title, systemImage: policy.systemImage)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(policyColor.opacity(0.12), in: Capsule())
            .foregroundStyle(policyColor)
    }

    private var policyColor: Color {
        switch policy {
        case .exact: return .green
        case .region: return .orange
        }
    }

    private func recommendationCard(_ recommendation: BookRecommendation) -> some View {
        Button {
            onFind(recommendation.book)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        BookCoverView(book: recommendation.book, width: 42)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.book.title)
                            .font(.subheadline.weight(.semibold))
                        Text(recommendation.book.author)
                            .font(.caption)
                            .foregroundStyle(LibraryTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(LibraryTheme.textMuted)
                if allowsDiscoveryActions {
                    Label("Find this book", systemImage: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LibraryTheme.accent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(LibraryTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!allowsDiscoveryActions)
    }
}

struct BookComparisonCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let comparison: BookComparison
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Label("BOOK COMPARISON", systemImage: "rectangle.2.swap")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(LibraryTheme.accent)
                Text("Two books. A new perspective.")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            comparisonLayout {
                bookColumn(comparison.first)
                bookColumn(comparison.second)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("\(comparison.similarity.formatted(.percent.precision(.fractionLength(0)))) content similarity", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: comparison.similarity)
                    .tint(LibraryTheme.accent)
                    .accessibilityHidden(true)
                Text("SHARED THEMES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(LibraryTheme.textMuted)
                    .padding(.top, 4)
                Text(comparison.sharedThemes.isEmpty ? "No shared themes are listed in this catalog." : comparison.sharedThemes.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textMuted)
            }
            .padding(16)
            .background(LibraryTheme.elevated, in: RoundedRectangle(cornerRadius: 18))

            Text("Similarity is based on catalog content. Ratings are demo data, not live reviews.")
                .font(.caption2)
                .foregroundStyle(LibraryTheme.textMuted)

            Button(action: onStartOver) {
                Label("Start over", systemImage: "viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(LibraryTheme.background)
            .buttonBorderShape(.roundedRectangle(radius: 12))
        }
        .padding(20)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .tint(LibraryTheme.accent)
    }

    private var comparisonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    private func bookColumn(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            BookCoverView(book: book, width: 84)
                .accessibilityHidden(true)
                .padding(.bottom, 3)
            Text(book.title)
                .font(.subheadline.weight(.bold))
            Text(book.author)
                .font(.caption)
                .foregroundStyle(LibraryTheme.textMuted)
            Text(book.genre)
                .font(.caption)
                .foregroundStyle(LibraryTheme.accent)
            Label("\(book.rating.formatted(.number.precision(.fractionLength(1)))) · demo rating", systemImage: "star.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LibraryTheme.textMuted)
            ReadingStatusMenu(book: book)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
