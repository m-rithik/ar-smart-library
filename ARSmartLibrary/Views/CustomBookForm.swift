import SwiftUI

struct CustomBookForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: LibrarySpaceController
    let onSave: (Book) -> Void

    @State private var title = ""
    @State private var author = ""
    @State private var genre = ""
    @State private var summary = ""
    @State private var keywords = ""
    @State private var rating = 0.0
    @State private var saveError: String?
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Title", hint: "Book title", text: $title)
                    field("Author", hint: "Author name", text: $author)
                } header: {
                    Text("Required")
                } footer: {
                    Text("Use the title printed on the cover or spine so the scanner can recognize it.")
                }

                Section("Optional details") {
                    field("Genre", hint: "e.g. Computer Science", text: $genre)
                    field("Description", hint: "What is this book about?", text: $summary)
                    field("Keywords", hint: "e.g. programming, algorithms", text: $keywords)
                    Picker("Your rating", selection: $rating) {
                        Text("Not rated").tag(0.0)
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value) / 5").tag(Double(value))
                        }
                    }
                }

                Section {
                    Label("Saved on this iPhone", systemImage: "iphone")
                    Text("Your book will appear in the library, title scanner, and shelf assignment list. Separate keywords with commas to help find related books.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = controller.customBookError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryTheme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add your book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || controller.customBookError != nil)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .alert("Discard this book?", isPresented: $confirmsDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("The book has not been saved. Your entered details will be lost.")
            }
            .alert("Could not add book", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .tint(LibraryTheme.accent)
    }

    private var hasChanges: Bool {
        [title, author, genre, summary, keywords].contains { !$0.isEmpty } || rating != 0
    }

    private func field(_ label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline)
            TextField(hint, text: text, axis: .vertical)
                .accessibilityLabel(label)
        }
    }

    private func save() {
        do {
            let book = try controller.addCustomBook(title: title, author: author, genre: genre,
                                                    summary: summary, keywords: keywords, rating: rating)
            onSave(book)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
