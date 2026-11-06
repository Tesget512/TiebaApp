import SwiftUI

/// 设置中心（对应 Android `SettingsPage` 及其子页）。
/// iOS 版合并为分组列表 + 子页面；写操作受安全模式约束（对齐 Android SafeModeInterceptor）。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var restartHint = false

    var body: some View {
        Form {
            Section {
                NavigationLink { AccountManageView() } label: {
                    Label("账号管理", systemImage: "person.crop.rectangle")
                }
            }

            Section("安全") {
                Toggle(isOn: $prefs.safeMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("安全模式")
                        Text("开启后所有写操作（发帖/点赞/签到等）将被拦截，客户端只读")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Toggle("无痕模式（不记录浏览历史）", isOn: $prefs.incognitoMode)
            }

            Section("外观") {
                NavigationLink { ThemeSettingsView() } label: {
                    Label("主题设置", systemImage: "paintpalette")
                }
                NavigationLink { FontScaleView() } label: {
                    Label("字体大小（\(FontScaleOption.label(for: prefs.fontScale))）",
                          systemImage: "textformat.size")
                }
                Toggle("单列列表", isOn: $prefs.listSingle)
            }

            Section("屏蔽") {
                NavigationLink { BlockListPage() } label: {
                    Label("屏蔽列表（黑/白名单）", systemImage: "nosign")
                }
                Toggle("隐藏被屏蔽内容", isOn: $prefs.hideBlockedContent)
                Toggle("屏蔽视频帖", isOn: $prefs.blockVideo)
            }

            if !prefs.safeMode {
                Section("签到") {
                    NavigationLink { OKSignSettingsView() } label: {
                        Label("一键签到", systemImage: "checkmark.seal")
                    }
                }
            }

            Section("其他") {
                Toggle("隐藏媒体（图片/视频）", isOn: $prefs.hideMedia)
                NavigationLink { AboutView() } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 主题设置（对应 Android AppThemePage 的 iOS 精简版）

struct ThemeSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var customHex = ""

    var body: some View {
        Form {
            Section("跟随系统") {
                Toggle("深色模式跟随系统", isOn: $prefs.followSystemNight)
            }

            Section("深色主题样式") {
                Picker("深色主题", selection: $prefs.darkTheme) {
                    ForEach([AppTheme.blueDark, .greyDark, .amoledDark]) { t in
                        Text(t.displayName).tag(t.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("自定义主色") {
                TextField("#RRGGBB（留空使用主题默认）", text: $customHex)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("应用自定义主色") {
                    let hex = customHex.trimmingCharacters(in: .whitespaces)
                    if hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil {
                        prefs.customPrimaryColor = hex
                    }
                }
                .disabled(customHex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil)
                if !prefs.customPrimaryColor.isEmpty {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hexString: prefs.customPrimaryColor))
                            .frame(width: 22, height: 22)
                        Text(prefs.customPrimaryColor).font(.footnote)
                        Spacer()
                        Button("清除") { prefs.customPrimaryColor = "" }
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
            }

            Section("App 图标") {
                AppIconPicker()
            }
        }
        .navigationTitle("主题设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 字体大小（对应 Android AppFontSizeActivity 六档）

struct FontScaleView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section {
                ForEach([0.8, 0.9, 1.0, 1.1, 1.2, 1.3], id: \.self) { scale in
                    Button {
                        prefs.fontScale = scale
                    } label: {
                        HStack {
                            Text(FontScaleOption.label(for: scale))
                                .font(.system(size: 16 * scale))
                            Spacer()
                            if abs(prefs.fontScale - scale) < 0.001 {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("预览：贴吧是一个基于兴趣的社区。当前缩放 \(Int(prefs.fontScale * 100))%")
                    .font(.system(size: 15 * prefs.fontScale))
            }
        }
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 一键签到设置（对应 Android OKSignSettingsPage）

struct OKSignSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var running = false
    @State private var progressText = ""
    @State private var resultText: String?

    var body: some View {
        Form {
            Section("自动签到") {
                Toggle("每日自动签到", isOn: $prefs.autoSign)
                if prefs.autoSign {
                    DatePicker("签到时间", selection: Binding(
                        get: { Self.time(from: prefs.autoSignTime) },
                        set: { prefs.autoSignTime = Self.string(from: $0) }),
                        displayedComponents: .hourAndMinute)
                }
            }

            Section("签到行为") {
                Toggle("慢速模式（每吧随机 3.5-8s，更安全）", isOn: $prefs.oksignSlowMode)
                Toggle("使用批量签到接口（msign）", isOn: $prefs.oksignUseOfficialOksign)
                Toggle("失败自动停止", isOn: $prefs.oksignFailAutoStop)
            }

            Section {
                Button {
                    Task { await runSign() }
                } label: {
                    if running {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("立即一键签到").frame(maxWidth: .infinity).bold()
                    }
                }
                .disabled(running || !appState.isLoggedIn)
                if !appState.isLoggedIn {
                    Text("请先登录").font(.footnote).foregroundStyle(.secondary)
                }
                if !progressText.isEmpty {
                    Text(progressText).font(.footnote).foregroundStyle(.secondary)
                }
                if let resultText {
                    Text(resultText).font(.footnote)
                }
            } footer: {
                Text("一键签到会模拟桌面小组件入口（from_widget=1）以获得双倍经验；签到结果按等级门槛与 msign 上限分批处理。")
            }
        }
        .navigationTitle("一键签到")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runSign() async {
        guard let account = appState.account else { return }
        running = true
        resultText = nil
        defer { running = false }
        await appState.refreshTbsIfNeeded()
        let ok = await OKSigner.run(
            account: appState.account ?? account,
            slowMode: prefs.oksignSlowMode,
            useMSign: prefs.oksignUseOfficialOksign,
            failAutoStop: prefs.oksignFailAutoStop) { p in
            if p.finished {
                progressText = ""
                resultText = p.errorText ?? (p.successCount > 0
                    ? "签到完成：成功 \(p.successCount)/\(p.total) 个吧"
                    : "没有可签到的吧")
            } else if !p.currentForum.isEmpty {
                progressText = "正在签到 (\(p.signedCount + 1)/\(p.total))：\(p.currentForum)吧"
            } else {
                progressText = "即将开始签到（共 \(p.total) 个吧）"
            }
        }
        // 记录当天已签
        if ok { prefs.signDay = Calendar.current.component(.day, from: Date()) }
    }

    private static func time(from s: String) -> Date {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        var c = DateComponents(); c.hour = parts.first ?? 9; c.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private static func string(from d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
    }
}

// MARK: - 屏蔽列表（对应 Android BlockListPage + BlockManager）

struct BlockListPage: View {
    @ObservedObject private var blockManager = BlockManager.shared
    @State private var newKeyword = ""
    @State private var isRegex = false
    @State private var category = 10  // 10=黑名单 11=白名单

    var body: some View {
        Form {
            Section("添加关键词屏蔽") {
                Picker("名单", selection: $category) {
                    Text("黑名单").tag(10)
                    Text("白名单").tag(11)
                }
                .pickerStyle(.segmented)
                TextField("关键词（多个用空格分隔）", text: $newKeyword)
                Toggle("按正则匹配", isOn: $isRegex)
                Button("添加") {
                    let kws = isRegex ? [newKeyword] : newKeyword.split(separator: " ").map(String.init)
                    blockManager.add(category: category, keywords: kws, isRegex: isRegex)
                    newKeyword = ""
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("黑名单") {
                if blockManager.blackList.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                }
                ForEach(blockManager.blackList, id: \.id) { b in
                    row(b)
                }
            }

            Section("白名单") {
                if blockManager.whiteList.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                }
                ForEach(blockManager.whiteList, id: \.id) { b in
                    row(b)
                }
            }
        }
        .navigationTitle("屏蔽设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ b: BlockManager.Block) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.keywords?.joined(separator: " ") ?? b.username ?? "").font(.subheadline)
                Text(b.isRegex ? "正则" : "关键词").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                blockManager.remove(id: b.id)
            } label: {
                Image(systemName: "trash")
            }
        }
    }
}

// MARK: - 账号管理（对应 Android AccountManagePage：多账号切换/新增/退出/复制BDUSS/小尾巴）

struct AccountManageView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false
    @State private var showTailEditor = false
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            if !appState.allAccounts.isEmpty {
                Section("账号") {
                    ForEach(appState.allAccounts, id: \.uid) { acc in
                        Button {
                            appState.switchAccount(uid: acc.uid)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: acc.avatarURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.name).foregroundStyle(.primary)
                                    Text("UID: \(acc.uid)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if acc.uid == appState.account?.uid {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }

            if let account = appState.account {
                Section("当前账号") {
                    Button("复制 BDUSS") {
                        UIPasteboard.general.string = account.bduss
                    }
                }
                Section("小尾巴") {
                    Button {
                        showTailEditor = true
                    } label: {
                        HStack {
                            Text("修改小尾巴")
                            Spacer()
                            Text(prefs.littleTail.isEmpty ? "未设置" : prefs.littleTail)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Section {
                    Button("退出当前账号", role: .destructive) {
                        appState.logout()
                    }
                }
            }

            Section {
                Button {
                    showLogin = true
                } label: {
                    Label("添加账号", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
        .navigationTitle("账号管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { LoginView() }
        .alert("修改小尾巴", isPresented: $showTailEditor) {
            TextField("小尾巴内容", text: $prefs.littleTail)
            Button("保存") { }
            Button("取消", role: .cancel) { }
        } message: {
            Text("小尾巴会附加在回复内容末尾（对应 Android little_tail 设置）")
        }
    }
}

// MARK: - 关于（对应 Android AboutPage + 7 连击彩蛋）

struct AboutView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var eggToast = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "b.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color(hexString: "#2E60B0"))
                        Text("TiebaLite iOS").font(.headline)
                        Text("v1.1 (P9)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .onTapGesture {
                    let now = Date()
                    if now.timeIntervalSince(lastTapTime) < 0.5 { tapCount += 1 } else { tapCount = 1 }
                    lastTapTime = now
                    if tapCount >= 7 {
                        prefs.showExperimentalFeatures.toggle()
                        eggToast = prefs.showExperimentalFeatures ? "实验性功能已开启" : "实验性功能已关闭"
                        tapCount = 0
                    }
                }
            } footer: {
                Text("iOS 原生重写版，协议 1:1 对齐 Android 主分支。仅供学习研究。")
            }

            Section("致谢") {
                Link("zzc10086/TiebaLite (Android)", destination: URL(string: "https://github.com/zzc10086/TiebaLite")!)
                Link("makise2060/FluxTie", destination: URL(string: "https://github.com/makise2060/FluxTie")!)
            }

            if prefs.showExperimentalFeatures {
                Section("实验性功能") {
                    Text("实验性功能已开启").font(.footnote).foregroundStyle(.orange)
                }
            }

            if !eggToast.isEmpty {
                Section { Text(eggToast).font(.footnote) }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 颜色扩展（主题自定义主色用）

extension Color {
    init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
