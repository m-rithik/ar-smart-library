import SwiftUI

enum LibraryTheme {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.075)
    static let surface = Color(red: 0.10, green: 0.13, blue: 0.13)
    static let elevated = Color(red: 0.15, green: 0.19, blue: 0.18)
    static let accent = Color(red: 0.70, green: 0.88, blue: 0.66)
    static let textMuted = Color(red: 0.65, green: 0.71, blue: 0.68)
}

/// Original, typographic catalog artwork; these are not edition cover images.
struct BookCoverView: View {
    let book: Book
    var width: CGFloat = 120

    private var palette: (Color, Color, String) {
        switch book.genre {
        case "Romance": return (Color(red: 0.79, green: 0.43, blue: 0.34), Color(red: 1, green: 0.85, blue: 0.65), "leaf")
        case "Gothic": return (Color(red: 0.28, green: 0.33, blue: 0.38), Color(red: 0.81, green: 0.77, blue: 0.62), "moon")
        case "Science Fiction": return (Color(red: 0.29, green: 0.38, blue: 0.57), Color(red: 0.85, green: 0.89, blue: 0.94), "sparkle")
        case "Adventure": return (Color(red: 0.17, green: 0.42, blue: 0.46), Color(red: 0.82, green: 0.90, blue: 0.82), "water.waves")
        case "Mystery": return (Color(red: 0.70, green: 0.58, blue: 0.29), Color(red: 0.18, green: 0.24, blue: 0.20), "eye")
        case "Coming of Age": return (Color(red: 0.40, green: 0.49, blue: 0.34), Color(red: 0.96, green: 0.87, blue: 0.68), "sun.max")
        default: return (Color(red: 0.25, green: 0.40, blue: 0.35), Color(red: 0.90, green: 0.76, blue: 0.48), "diamond")
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            palette.0
            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<4) { index in
                        Ellipse()
                            .stroke(palette.1.opacity(0.35), lineWidth: 0.8)
                            .frame(width: geometry.size.width * (0.52 + Double(index) * 0.16),
                                   height: geometry.size.height * 0.38)
                            .rotationEffect(.degrees(Double(index) * 28))
                    }
                    Image(systemName: palette.2)
                        .font(.system(size: width * 0.23, weight: .ultraLight))
                        .foregroundStyle(palette.1)
                }
                .position(x: geometry.size.width * 0.54, y: geometry.size.height * 0.62)
            }
            LinearGradient(colors: [.black.opacity(0.25), .clear, .white.opacity(0.12), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.1)
            VStack(alignment: .leading, spacing: width * 0.055) {
                Text("THE LIBRARY COLLECTION")
                    .font(.system(size: width * 0.038, weight: .semibold, design: .monospaced))
                    .tracking(width * 0.01)
                Rectangle().fill(palette.1.opacity(0.5)).frame(height: 0.7)
                Text(book.title)
                    .font(.system(size: width * 0.14, weight: .medium, design: .serif))
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(book.author.uppercased())
                    .font(.system(size: width * 0.052, weight: .semibold, design: .monospaced))
                    .tracking(width * 0.008)
                    .lineLimit(2)
            }
            .foregroundStyle(palette.1)
            .padding(width * 0.12)
            .padding(.leading, width * 0.02)
        }
        .frame(width: width, height: width * 1.45)
        .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 3, y: 6)
        .accessibilityHidden(true)
    }
}

struct ReadingStatusMenu: View {
    @EnvironmentObject private var readingList: ReadingListStore
    let book: Book

    private var status: ReadingStatus? { readingList.status(for: book.id) }

    var body: some View {
        Menu {
            ForEach(ReadingStatus.allCases) { option in
                Button {
                    readingList.setStatus(option, for: book.id)
                } label: {
                    Label(option.title, systemImage: option == status ? "checkmark" : option.systemImage)
                }
            }
            if status != nil {
                Divider()
                Button("Remove from my list", role: .destructive) {
                    readingList.setStatus(nil, for: book.id)
                }
            }
        } label: {
            Label(status?.title ?? "Save to my list", systemImage: status?.systemImage ?? "bookmark")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(LibraryTheme.accent)
        .accessibilityLabel("Reading list for \(book.title)")
        .accessibilityValue(status?.title ?? "Not saved")
        .sensoryFeedback(.selection, trigger: status)
    }
}
