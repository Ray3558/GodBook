import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .comicDestinations()
            }
            .tabItem { Label("探索", systemImage: "square.grid.2x2.fill") }

            NavigationStack {
                LibraryView()
                    .comicDestinations()
            }
            .tabItem { Label("書庫", systemImage: "books.vertical.fill") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
        }
        .task { DownloadManager.shared.resumeQueued() }
    }
}

extension View {
    /// 註冊詳情頁與標籤搜尋頁的導覽目的地。
    func comicDestinations() -> some View {
        navigationDestination(for: ComicSummary.self) { DetailView(summary: $0) }
            .navigationDestination(for: SearchRoute.self) { SearchResultsView(route: $0) }
    }
}
