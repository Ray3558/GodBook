import SwiftUI

struct RootView: View {
    @State private var tab = AppSettings.shared.initialTab

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView()
                    .comicDestinations()
            }
            .tabItem { Label("探索", systemImage: "square.grid.2x2.fill") }
            .tag(0)

            NavigationStack {
                LibraryView()
                    .comicDestinations()
            }
            .tabItem { Label("書庫", systemImage: "books.vertical.fill") }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
            .tag(2)
        }
        .overlay { ToastOverlay() }
        .task {
            DownloadManager.shared.resumeQueued()
            await VeneraStore.shared.bootstrap()
            await FollowStore.shared.checkIfDue(favorites: FavoritesStore.shared)
        }
    }
}

extension View {
    /// 註冊詳情頁與標籤搜尋頁的導覽目的地。
    func comicDestinations() -> some View {
        navigationDestination(for: ComicSummary.self) { DetailView(summary: $0) }
            .navigationDestination(for: SearchRoute.self) { SearchResultsView(route: $0) }
    }
}
