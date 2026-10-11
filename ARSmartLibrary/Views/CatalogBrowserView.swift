import SwiftUI

struct CatalogBrowserView: View {
    @ObservedObject var controller: LibrarySpaceController
    @EnvironmentObject private var readingList: ReadingListStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let canUseAR: Bool
    let onRetryAlignment: () -> Void

    @State private var query = ""
    @State private var genre = ""
    @State private var locatedOnly = false
    @State private var savedOnly = false
    @State private var readingStatus: ReadingStatus?
    @State private var sort: CatalogSort = .title
    @State private var showsGrid = true
    @FocusState private var searchFocused: Bool

    private var genres: [String] { Set(controller.catalog.map(\.genre)).sorted() }
    private var locatedBookIDs: Set<String> {
        Set(controller.catalog.filter { controller.space?.placement(for: $0.id) != nil }.map(\.id))
    }
    private var savedCount: Int { controller.catalog.filter { readingList.status(for: $0.id) != nil }.count }
    private var hasFilters: Bool { !query.isEmpty || !genre.isEmpty || locatedOnly || readingStatus != nil }
    private var books: [Book] {
        let source = controller.catalog.filter { book in
            let status = readingList.status(for: book.id)
            return (!savedOnly || status != nil) && (readingStatus == nil || status == readingStatus)
        }
        return CatalogQuery.books(in: source, query: query, genre: genre, locatedOnly: locatedOnly,
                                  locatedBookIDs: locatedBookIDs, sort: sort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                searchBar
                collectionPicker
                if savedOnly { readingFilters }
                if !savedOnly, !hasFilters, let featured = controller.catalog.first {
                    spotlight(featured)
                }
                genreFilters
                if controller.space != nil, !controller.isLocalized, canUseAR { alignmentCard }
                resultsHeader
                if books.isEmpty {
                    emptyState
                } else if showsGrid && !dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                              alignment: .leading, spacing: 22) {
                        ForEach(books) { book in bookTile(book) }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(books) { book in bookRow(book) }
                    }
                }
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LibraryTheme.background)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("A LITTLE CURIOSITY GOES A LONG WAY")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(LibraryTheme.accent)
                Spacer(minLength: 0)
                Image(systemName: "sparkle").foregroundStyle(LibraryTheme.accent)
            }
            Text(savedOnly ? "Make room\nfor great stories." : "Find your\nnext chapter.")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                statistic(controller.catalog.count, "titles")
                statistic(genres.count, "genres")
                statistic(locatedBookIDs.count, "on the map")
            }
            .padding(.top, 2)
        }
    }

    private func statistic(_ count: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(count.formatted()).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
            Text(title).font(.caption).foregroundStyle(LibraryTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(LibraryTheme.accent)
            TextField("Title, author, or a little inspiration", text: $query)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("Search title, author or topic")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .foregroundStyle(LibraryTheme.textMuted)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.07)) }
    }

    private var collectionPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                collectionOptions.pickerStyle(.menu)
            } else {
                collectionOptions.pickerStyle(.segmented)
            }
        }
        .onChange(of: savedOnly) { _, _ in readingStatus = nil }
    }

    private var collectionOptions: some View {
        Picker("Collection", selection: $savedOnly) {
            Text("Explore").tag(false)
            Text("My list · \(savedCount)").tag(true)
        }
    }

    private var readingFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All saved", selected: readingStatus == nil) { readingStatus = nil }
                ForEach(ReadingStatus.allCases) { status in
                    filterChip(status.title, selected: readingStatus == status) { readingStatus = status }
                }
            }
        }
    }

    private func spotlight(_ book: Book) -> some View {
        NavigationLink(value: book) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("IN THE SPOTLIGHT", systemImage: "sun.max")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(LibraryTheme.accent)
                    Text(book.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(book.author)
                        .font(.caption).foregroundStyle(LibraryTheme.textMuted)
                    Label("Meet your next read", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium)).foregroundStyle(LibraryTheme.accent)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    BookCoverView(book: book, width: 106).rotationEffect(.degrees(7))
                        .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background {
                LinearGradient(colors: [LibraryTheme.elevated, LibraryTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(LibraryTheme.accent.opacity(0.12)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("In the spotlight: \(book.title) by \(book.author). View details.")
    }

    private var genreFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All genres", selected: genre.isEmpty) { genre = "" }
                ForEach(genres, id: \.self) { value in
                    filterChip(value, selected: genre == value) { genre = value }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? LibraryTheme.background : LibraryTheme.textMuted)
                .background(selected ? LibraryTheme.accent : LibraryTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(savedOnly ? "Your reading shelf" : "The collection")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(books.count.formatted())
                    .font(.caption.monospacedDigit()).foregroundStyle(LibraryTheme.textMuted)
                Spacer(minLength: 0)
                Menu {
                    Picker("Sort books", selection: $sort) {
                        ForEach(CatalogSort.allCases) { option in Text(option.title).tag(option) }
                    }
                    Toggle("With shelf directions", isOn: $locatedOnly)
                } label: {
                    Image(systemName: locatedOnly ? "line.3.horizontal.decrease.circle.fill" : "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Sort and filter books")
                .accessibilityValue("\(sort.title)\(locatedOnly ? ", with shelf directions" : "")")
                if !dynamicTypeSize.isAccessibilitySize {
                    Button { showsGrid.toggle() } label: {
                        Image(systemName: showsGrid ? "list.bullet" : "square.grid.2x2")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(showsGrid ? "Show as list" : "Show as grid")
                }
            }
            if hasFilters {
                HStack {
                    Text(locatedOnly ? "With shelf directions · \(sort.title)" : "Sorted by \(sort.title.lowercased())")
                        .font(.caption).foregroundStyle(LibraryTheme.textMuted)
                    Spacer()
                    Button("Reset filters", action: resetFilters).font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func bookTile(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: book) {
                VStack(alignment: .leading, spacing: 10) {
                    BookCoverView(book: book, width: 124)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(2).frame(minHeight: 40, alignment: .topLeading)
                    Text(book.author).font(.caption).foregroundStyle(LibraryTheme.textMuted).lineLimit(1)
                    bookMetadata(book)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            ReadingStatusMenu(book: book).font(.caption)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func bookRow(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: book) {
                HStack(alignment: .top, spacing: 16) {
                    if !dynamicTypeSize.isAccessibilitySize { BookCoverView(book: book, width: 66) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title).font(.headline).foregroundStyle(.primary)
                        Text(book.author).font(.subheadline).foregroundStyle(LibraryTheme.textMuted)
                        bookMetadata(book)
                        if let placement = controller.space?.placement(for: book.id) {
                            Label("\(placement.shelf.label) · \(placement.location.slotLabel)", systemImage: "location")
                                .font(.caption).foregroundStyle(LibraryTheme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(LibraryTheme.textMuted)
                }
            }
            .buttonStyle(.plain)
            ReadingStatusMenu(book: book)
        }
        .padding(16)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bookMetadata(_ book: Book) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(book.genre).lineLimit(1)
                Spacer(minLength: 4)
                Label(book.rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(book.genre)
                Label(book.rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(LibraryTheme.textMuted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.genre), demo rating \(book.rating.formatted()) out of 5")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(controller.catalog.isEmpty ? "The catalog is unavailable" : savedOnly && savedCount == 0 ? "Your next reads live here" : "No books found",
                  systemImage: savedOnly ? "bookmark" : "magnifyingglass")
        } description: {
            Text(controller.catalog.isEmpty ? "Reopen the app to load the bundled books." : savedOnly && savedCount == 0
                 ? "Save a book to build your own reading shelf. Your list stays on this iPhone."
                 : locatedOnly && locatedBookIDs.isEmpty ? "No shelf locations have been assigned yet. Browse all books, or map a shelf in Library setup."
                 : "Try another title, author or topic, or clear your filters.")
        } actions: {
            if !controller.catalog.isEmpty {
                Button(savedOnly && savedCount == 0 ? "Explore books" : "Reset filters") {
                    resetFilters()
                    if savedCount == 0 { savedOnly = false }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 20)
    }

    private var alignmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your shelves are waiting", systemImage: "viewfinder").font(.subheadline.weight(.semibold))
            Text("Return to the saved entrance view to align the room before following directions.")
                .font(.caption).foregroundStyle(LibraryTheme.textMuted)
            if controller.hasSavedSpace {
                Button("Retry room alignment", action: onRetryAlignment)
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(controller.isSaving)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Label("A whole library. Entirely on your device.", systemImage: "iphone")
                .font(.caption.weight(.medium))
            Text("Demo catalog ratings · Original catalog artwork")
                .font(.caption2)
            if !canUseAR {
                Text("Scan books and follow shelf directions on an AR-capable iPhone.")
                    .font(.caption2)
            }
        }
        .foregroundStyle(LibraryTheme.textMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func resetFilters() {
        query = ""
        genre = ""
        locatedOnly = false
        readingStatus = nil
        searchFocused = false
    }
}
