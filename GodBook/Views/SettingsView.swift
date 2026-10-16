import PhotosUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var settings: AppSettings

    @State private var photoItem: PhotosPickerItem?
    @State private var jmPassword = ""
    @State private var jmBusy = false
    @State private var jmMessage: String?
    @State private var downloadSize: Int64 = 0
    @State private var confirmClear = false
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var venera: VeneraStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                themeCard
                backgroundCard
                glassCard
                veneraCard
                nhentaiCard
                jmCard
                readerCard
                advancedCard
                downloadCard
                aboutCard
            }
            .padding(16)
        }
        .themedScreen()
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    theme.setBackgroundImage(data: data)
                }
                photoItem = nil
            }
        }
    }

    // MARK: 主題

    private var themeCard: some View {
        SettingsCard(title: "主題色", systemImage: "paintpalette.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemePreset.all) { preset in
                        Button {
                            withAnimation(.snappy) {
                                theme.config.accentHex = preset.accent
                                theme.config.gradientStartHex = preset.start
                                theme.config.gradientEndHex = preset.end
                                if theme.config.backgroundMode == .system || theme.config.backgroundMode == .solid {
                                    theme.config.backgroundMode = .gradient
                                }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(hex: preset.start), Color(hex: preset.end)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay(Circle().stroke(Color(hex: preset.accent), lineWidth: 3))
                                    .frame(width: 44, height: 44)
                                Text(preset.name).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            ColorPicker("強調色", selection: theme.colorBinding(\.accentHex), supportsOpacity: false)
            Picker("外觀", selection: $theme.config.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var backgroundCard: some View {
        SettingsCard(title: "背景", systemImage: "photo.fill") {
            Picker("背景", selection: $theme.config.backgroundMode) {
                ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch theme.config.backgroundMode {
            case .system:
                Text("使用系統預設背景").font(.footnote).foregroundStyle(.secondary)
            case .solid:
                ColorPicker("背景顏色", selection: theme.colorBinding(\.solidHex), supportsOpacity: false)
            case .gradient:
                ColorPicker("漸層起點", selection: theme.colorBinding(\.gradientStartHex), supportsOpacity: false)
                ColorPicker("漸層終點", selection: theme.colorBinding(\.gradientEndHex), supportsOpacity: false)
            case .image:
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(theme.backgroundImage == nil ? "選擇背景圖片" : "更換背景圖片", systemImage: "photo.on.rectangle")
                }
                if theme.backgroundImage != nil {
                    LabeledSlider(title: "模糊", value: $theme.config.imageBlur, range: 0...30)
                    LabeledSlider(title: "壓暗", value: $theme.config.imageDim, range: 0...0.8)
                    Button("移除圖片", role: .destructive) { theme.clearBackgroundImage() }
                }
            }
        }
    }

    private var glassCard: some View {
        SettingsCard(title: "液態玻璃", systemImage: "drop.fill") {
            Toggle("啟用玻璃效果", isOn: $theme.config.useGlass)
            if theme.config.useGlass {
                LabeledSlider(title: "染色強度", value: $theme.config.glassTint, range: 0...0.6)
            }
            if #available(iOS 26.0, *) {
                Text("目前系統支援原生液態玻璃 (iOS 26)。").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("iOS 26 以下以模糊材質模擬；升級到 iOS 26 即為原生液態玻璃。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("還原預設主題", role: .destructive) { theme.reset() }
        }
    }

    // MARK: 來源

    private var veneraCard: some View {
        SettingsCard(title: "來源管理", systemImage: "puzzlepiece.extension.fill") {
            NavigationLink {
                VeneraSourcesView()
            } label: {
                HStack {
                    Text("啟用 / 停用來源、管理 venera 漫畫源（\(venera.sources.count) 個）")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("相容 venera 的 JavaScript 漫畫源；內建一批來源，也可自行新增。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var nhentaiCard: some View {
        SettingsCard(title: "nhentai", systemImage: "network") {
            TextField("鏡像網域", text: $settings.nhMirror)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("API Key（選填）", text: $settings.nhApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Text("預設 nhentai.net。若遇到 403，可填入 API Key 或更換鏡像。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var jmCard: some View {
        SettingsCard(title: "禁漫", systemImage: "person.crop.circle") {
            if settings.jmLoggedIn {
                HStack {
                    Label(settings.jmUsername, systemImage: "checkmark.seal.fill")
                    Spacer()
                    Button("登出", role: .destructive) { Task { await JMClient.shared.logout() } }
                }
            } else {
                TextField("帳號", text: $settings.jmUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("密碼", text: $jmPassword).textFieldStyle(.roundedBorder)
                GlassButton(title: jmBusy ? "登入中…" : "登入", systemImage: "arrow.right.circle.fill", prominent: true) {
                    login()
                }
                .disabled(jmBusy || settings.jmUsername.isEmpty || jmPassword.isEmpty)
            }
            if let jmMessage {
                Text(jmMessage).font(.footnote).foregroundStyle(.secondary)
            }
            TextField("自訂 API 網域（選填，逗號分隔）", text: $settings.jmCustomDomain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Text("預設會自動向官方網域伺服器取得最新 API 網域。登入後可使用雲端收藏。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func login() {
        jmBusy = true
        jmMessage = nil
        let user = settings.jmUsername
        let pass = jmPassword
        Task {
            do {
                try await JMClient.shared.login(username: user, password: pass)
                jmMessage = "登入成功"
                jmPassword = ""
            } catch {
                jmMessage = error.localizedDescription
            }
            jmBusy = false
        }
    }

    private var readerCard: some View {
        SettingsCard(title: "閱讀", systemImage: "book.fill") {
            Picker("閱讀方式", selection: $settings.readerMode) {
                ForEach(ReaderMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private var advancedCard: some View {
        SettingsCard(title: "進階", systemImage: "gearshape.2.fill") {
            link("網路（代理、憑證）", systemImage: "network") { NetworkSettingsView() }
            link("快取、備份與 WebDAV", systemImage: "externaldrive.fill") { CacheDataSettingsView() }
            link("安全性（App 鎖）", systemImage: "lock.shield.fill") { SecuritySettingsView() }
        }
    }

    private func link<Destination: View>(_ title: String, systemImage: String,
                                         @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var downloadCard: some View {
        SettingsCard(title: "下載", systemImage: "arrow.down.circle.fill") {
            Stepper("同時下載圖片數：\(settings.downloadConcurrency)", value: $settings.downloadConcurrency, in: 1...8)
            Toggle("翻譯 nhentai 標籤（繁體中文）", isOn: $settings.translateTags)
            HStack {
                Text("已佔用空間")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)).foregroundStyle(.secondary)
            }
            Button("清除所有下載", role: .destructive) { confirmClear = true }
                .disabled(downloads.items.isEmpty)
            Text("下載與匯出的檔案位於「檔案」App → GodBook → Downloads / Exports。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task(id: downloads.items.map(\.done).reduce(0, +)) {
            downloadSize = await Task.detached { DownloadStorage.totalSize() }.value
        }
        .confirmationDialog("確定要刪除所有已下載內容？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("刪除全部", role: .destructive) { downloads.removeAll() }
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "關於", systemImage: "info.circle.fill") {
            Text("""
            GodBook 整合 nhentai 與禁漫兩個來源。
            nhentai 的 API 流程參考 NClientV3 (Apache-2.0)；禁漫的 API 協定與下載流程參考 jmcomic (MIT) 與 jmcomic-downloader (MIT)。
            標籤翻譯來自 EhTagTranslation Database（經 venera 整理）。
            本 App 僅為第三方客戶端，內容版權屬原網站與作者所有。
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 元件

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
        }
    }
}
