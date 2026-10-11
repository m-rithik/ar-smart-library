import SwiftUI

@main
struct ARSmartLibraryApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["AR_SMART_LIBRARY_TESTING"] != "1" {
                ScannerView()
                    .preferredColorScheme(.dark)
            } else {
                Color.clear
            }
        }
    }
}
