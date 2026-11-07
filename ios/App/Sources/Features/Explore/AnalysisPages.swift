import SwiftUI
import UIKit
import Photos

/// 发言分析（对应 Android `ui/page/analysis/*` 的 iOS 版）：
/// 拉取用户最近 N 页主题贴+回复，聚合月份/时段/吧/词频四个维度。
struct PostAnalysisPage: View {
    let uid: Int64
    let name: String

    @State private var result: AnalysisResult?
    @State private var isLoading = false
    @State private var progressText = ""
    @State private var errorText: String?

    struct Record {
        var isThread: Bool
        var createTimeSec: Int64
        var forumName: String
        var title: String
        var content: String
    }

    struct Bucket: Identifiable {
        let key: String
        let count: Int
        var id: String { key }
    }

    struct AnalysisResult {
        var total = 0
        var threadCount = 0
        var replyCount = 0
        var forumCount = 0
        var monthBuckets: [Bucket] = []
        var hourBuckets: [Bucket] = []
        var forumBuckets: [Bucket] = []
        var wordBuckets: [Bucket] = []
    }

    var body: some View {
        Group {
            if isLoading && result == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(progressText).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, result == nil {
                UnavailableView(title: "加载失败", systemImage: "chart.bar", description: err)
            } else if let result {
                content(result)
            }
        }
        .navigationTitle("\(name)的发言分析")
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarHidden()
        .task { if result == nil { await analyze() } }
    }

    @ViewBuilder
    private func content(_ r: AnalysisResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 概览
                HStack {
                    overview("总发言", r.total)
                    Divider()
                    overview("主题贴", r.threadCount)
                    Divider()
                    overview("回复", r.replyCount)
                    Divider()
                    overview("涉及吧", r.forumCount)
                }
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                // 按月
                section("按月统计") {
                    let maxV = max(1, r.monthBuckets.map(\.count).max() ?? 1)
                    ForEach(r.monthBuckets) { b in
                        HStack(spacing: 8) {
                            Text(b.key).font(.caption2.monospacedDigit()).frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.blue.opacity(0.15))
                                    Capsule().fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat(b.count) / CGFloat(maxV))
                                }
                            }
                            .frame(height: 12)
                            Text("\(b.count)").font(.caption2.monospacedDigit()).frame(width: 32)
                        }
                    }
                }

                // 按时段
                section("按时段统计") {
                    let maxV = max(1, r.hourBuckets.map(\.count).max() ?? 1)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(r.hourBuckets) { b in
                            VStack(spacing: 2) {
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.orange)
                                        .frame(height: max(2, geo.size.height * CGFloat(b.count) / CGFloat(maxV)))
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                                .frame(height: 60)
                                Text(String(b.key.prefix(2)))
                                    .font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // 吧排名
                section("常驻吧 TOP10") {
                    ForEach(Array(r.forumBuckets.enumerated()), id: \.offset) { idx, b in
                        HStack {
                            Text("\(idx + 1)").font(.caption.monospacedDigit())
                                .foregroundStyle(idx < 3 ? .red : .secondary).frame(width: 20)
                            Text(b.key).font(.footnote).lineLimit(1)
                            Spacer()
                            Text("\(b.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }

                // 高频词
                section("高频词") {
                    FlowLayoutView(items: r.wordBuckets.prefix(30).map { "\($0.key) \($0.count)" })
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func overview(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(shortNum(Int64(value))).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 分析逻辑（对应 Android PostAnalysisViewModel/AnalysisRepository）

    private func analyze() async {
        isLoading = true
        defer { isLoading = false }
        let maxPages = 5
        var records: [Record] = []
        for isThread in [true, false] {
            for page in 1...maxPages {
                progressText = "拉取\(isThread ? "主题贴" : "回复")第 \(page)/\(maxPages) 页…"
                do {
                    let data = try await TiebaExtraEndpoints.userPost(
                        client: .shared, uid: uid, page: page, isThread: isThread)
                    if data.postList.isEmpty { break }
                    for p in data.postList {
                        records.append(Record(
                            isThread: isThread,
                            createTimeSec: Int64(p.createTime),
                            forumName: p.forumName,
                            title: p.title,
                            content: p.contentThread))
                    }
                } catch {
                    break
                }
            }
        }
        guard !records.isEmpty else {
            errorText = "没有可分析的发言（或接口未返回数据）"
            return
        }
        result = Self.aggregate(records)
    }

    static func aggregate(_ records: [Record]) -> AnalysisResult {
        var r = AnalysisResult()
        r.total = records.count
        r.threadCount = records.filter(\.isThread).count
        r.replyCount = r.total - r.threadCount

        // 按月（对齐 Android monthKeyOf：yyyy-MM）
        var monthMap: [String: Int] = [:]
        var hourCounts = [Int](repeating: 0, count: 24)
        var forumMap: [String: Int] = [:]
        var allText: [String] = []
        let dfMonth = DateFormatter()
        dfMonth.locale = Locale(identifier: "zh_CN")
        dfMonth.dateFormat = "yyyy-MM"
        let cal = Calendar(identifier: .gregorian)
        for rec in records {
            let date = Date(timeIntervalSince1970: TimeInterval(rec.createTimeSec))
            monthMap[dfMonth.string(from: date), default: 0] += 1
            hourCounts[cal.component(.hour, from: date)] += 1
            if !rec.forumName.isEmpty { forumMap[rec.forumName, default: 0] += 1 }
            allText.append("\(rec.title)\n\(rec.content)")
        }
        r.forumCount = forumMap.count
        r.monthBuckets = monthMap.sorted { $0.key < $1.key }.map { Bucket(key: $0.key, count: $0.value) }
        r.hourBuckets = (0..<24).map { Bucket(key: String(format: "%02d时", $0), count: hourCounts[$0]) }
        r.forumBuckets = forumMap.sorted { $0.value > $1.value }.prefix(10)
            .map { Bucket(key: $0.key, count: $0.value) }
        r.wordBuckets = TextAnalyzer.keywords(allText, limit: 50)
            .map { Bucket(key: $0.key, count: $0.value) }
        return r
    }
}

/// 中文分词统计（对应 Android `TextAnalyzer`：2-gram/3-gram + 停用字过滤）
enum TextAnalyzer {
    /// 单字停用词
    static let stopChars: Set<Character> = ["的", "了", "是", "在", "我", "有", "和", "就",
                                            "不", "人", "都", "一", "上", "也", "很",
                                            "到", "说", "要", "去", "你", "会", "着",
                                            "看", "好", "这", "那", "吗", "吧", "啊",
                                            "呢", "呀", "么"]
    /// 多字停用词（整词匹配）
    static let stopWords: Set<String> = ["没有", "自己", "什么", "还是", "就是", "但是",
                                          "可以", "因为", "所以", "如果", "现在", "时候", "一个"]
    static let chineseRun = try! NSRegularExpression(pattern: "[\\u4e00-\\u9fa5]+")

    static func isStop(_ gram: String) -> Bool {
        if stopWords.contains(gram) { return true }
        return gram.contains(where: { stopChars.contains($0) })
    }

    static func keywords(_ texts: [String], limit: Int = 50) -> [(key: String, value: Int)] {
        var gram2: [String: Int] = [:]
        var gram3: [String: Int] = [:]
        for text in texts {
            for match in chineseRun.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(match.range, in: text) else { continue }
                let chars = Array(String(text[r]))
                for i in 0..<max(0, chars.count - 1) {
                    let g2 = String(chars[i...min(i + 1, chars.count - 1)])
                    if g2.count == 2, !isStop(g2) { gram2[g2, default: 0] += 1 }
                }
                for i in 0..<max(0, chars.count - 2) {
                    let g3 = String(chars[i...min(i + 2, chars.count - 1)])
                    if g3.count == 3, !isStop(g3) { gram3[g3, default: 0] += 1 }
                }
            }
        }
        // 3-gram(≥2) 压制其最优 2-gram 子串（对齐 Android 逻辑）
        var suppressed = Set<String>()
        for (g3, c3) in gram3 where c3 >= 2 {
            for i in 0...1 {
                let sub = String(Array(g3)[i...i + 1])
                if let c2 = gram2[sub], Double(c3) >= Double(c2) * 0.7 {
                    suppressed.insert(sub)
                }
            }
        }
        var result: [(String, Int)] = []
        for (g3, c3) in gram3 where c3 >= 2 { result.append((g3, c3)) }
        for (g2, c2) in gram2 where c2 >= 2 && !suppressed.contains(g2) { result.append((g2, c2)) }
        return result.sorted { $0.1 > $1.1 }.prefix(limit).map { ($0.0, $0.1) }
    }
}

/// 简易流式布局（词云/标签用）
struct FlowLayoutView: View {
    let items: [String]

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width {
                                width = 0
                                height -= d.height + 6
                            }
                            let result = width
                            if item == items.last { width = 0 } else { width -= d.width + 6 }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: CGFloat((items.count / 6 + 1)) * 34)
    }
}

// MARK: - 图片查看器（对应 Android PhotoViewActivity：横向翻页 + 下载/分享）

struct PhotoViewPage: View {
    let urls: [String]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var toastText: String?

    var body: some View {
        Group {
            if urls.isEmpty {
                UnavailableView(title: "无图片", systemImage: "photo")
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { idx, urlStr in
                        ZoomableImage(urlString: urlStr)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .background(.black)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !urls.isEmpty, currentIndex < urls.count {
                    Button {
                        saveCurrent()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    if let u = URL(string: urls[currentIndex]) {
                        ShareLink(item: u) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toastText {
                Text(toastText).font(.footnote).padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .task { try? await Task.sleep(nanoseconds: 1_500_000_000); self.toastText = nil }
            }
        }
        .onAppear {
            currentIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        }
    }

    private func saveCurrent() {
        let urlStr = urls[currentIndex]
        guard let url = tiebaImageURL(urlStr) else {
            toastText = "图片地址无效"
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                try await PhotoSaver.save(image)
                toastText = "已保存到相册"
            } catch {
                toastText = "保存失败: \(error.localizedDescription)"
            }
        }
    }
}

@MainActor
enum PhotoSaver {
    static func save(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    cont.resume(throwing: URLError(.userAuthenticationRequired))
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { ok, err in
                    if let err { cont.resume(throwing: err) } else { cont.resume() }
                }
            }
        }
    }
}

/// 贴吧图片 URL 解析：含中文/空格等未转义字符时百分号编码兜底
func tiebaImageURL(_ s: String) -> URL? {
    URL(string: s)
        ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)
}

/// 可双指缩放图片
struct ZoomableImage: View {
    let urlString: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        VStack {
            if let url = tiebaImageURL(urlString) {
                RemoteImage(url: url, contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(5, lastScale * value))
                            }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2.5; lastScale = scale }
                    }
            } else {
                // URL 无法解析：给出可见的失败态而非黑屏
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("图片地址无效").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
