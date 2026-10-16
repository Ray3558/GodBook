import SwiftUI

@main
struct GodBookApp: App {
    @StateObject private var theme = ThemeStore()
    @StateObject private var library = LibraryStore()
    private let settings = AppSettings.shared
    private let downloads = DownloadManager.shared
    private let venera = VeneraStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(downloads)
                .environmentObject(venera)
                .tint(theme.accent)
                .preferredColorScheme(theme.preferredScheme)
        }
    }
}
