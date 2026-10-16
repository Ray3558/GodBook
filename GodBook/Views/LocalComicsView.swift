import SwiftUI
import UniformTypeIdentifiers

struct LocalComicsView: View {
    @EnvironmentObject private var local: LocalLibrary
    @State private var importing = false
    @State private var message: String?
    @State private var renaming: ComicSummary?
    @State private var renameText = ""
    @State private var exported: ExportedFile?
    @State private var busy = false

    private static var importTypes: [UTType] {
        var types: [UTType] = [.zip, .pdf, .folder]
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        return types
    }

    var body: some View {
        VStack(spacing: 12) {
            GlassButton(title: local.isImporting ? "匯入中…" : "匯入漫畫", systemImage: "square.and.arrow.down", prominent: true) {
                importing = true
            }
            .disabled(local.isImporting)
            .padding(.horizontal, 12)

            Text("支援 CBZ / ZIP / EPUB / PDF 與圖片資料夾（含子資料夾分章）。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            if let message { Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16) }

            if local.comics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.largeTitle)
                    Text("還沒有匯入的漫畫")
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(local.comics) { comic in
                        NavigationLink(value: comic) { ComicCard(comic: comic) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { renameText = comic.title; renaming = comic } label: { Label("重新命名", systemImage: "pencil") }
                                Menu("匯出") {
                                    ForEach(ExportFormat.allCases) { format in
                                        Button(format.title) { export(comic, format) }
                                    }
                                }
                                Button(role: .destructive) { local.remove(comic) } label: { Label("刪除", systemImage: "trash") }
                            }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .overlay { if busy { ProgressView().padding().glassCard() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            message = nil
            Task {
                for url in urls {
                    do { try await local.importItem(at: url) }
                    catch { message = "匯入「\(url.lastPathComponent)」失敗：\(error.localizedDescription)" }
                }
            }
        }
        .alert("重新命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("標題", text: $renameText)
            Button("確定") { if let comic = renaming { local.rename(comic, to: renameText) } }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $exported) { ShareSheet(urls: [$0.url]) }
    }

    private func export(_ comic: ComicSummary, _ format: ExportFormat) {
        busy = true
        Task {
            do {
                let url = try await Task.detached { try ComicExport.export(comic, as: format) }.value
                exported = ExportedFile(url: url)
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
