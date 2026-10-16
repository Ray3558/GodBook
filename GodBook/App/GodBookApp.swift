import SwiftUI

@main
struct GodBookApp: App {
    @StateObject private var theme = ThemeStore()
    @StateObject private var library = LibraryStore()
    private let settings = AppSettings.shared
    private let downloads = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(downloads)
                .tint(theme.accent)
                .preferredColorScheme(theme.preferredScheme)
        }
    }
}
