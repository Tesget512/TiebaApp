import SwiftUI
import UIKit

/// 图片查看器：UI 用成熟库 SKPhotoBrowser（ios/ThirdParty/SKPhotoBrowser，
/// 浅克隆官方仓库编入主 target；分页/双击缩放/保存/分享/长按菜单/滑动关闭），
/// 数据层仍走本项目对齐 Android 的 picpage 协议流
/// （`/c/f/pb/picpage` → img.original.original_src，失败回退传入列表）。
struct SKPhotoBrowserHost: View {
    let initialItems: [PicViewItem]
    let initialIndex: Int
    var context: PicPageContext? = nil

    /// nil = 正在解析图集（短超时，失败直接用传入列表）
    @State private var resolved: (items: [PicViewItem], index: Int)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let r = resolved {
                SKPhotoBrowserView(photos: r.items, initialIndex: r.index)
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("图片加载中…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .task {
            resolved = await Self.resolveGallery(initialItems: initialItems,
                                                 initialIndex: initialIndex,
                                                 context: context)
        }
    }

    /// picpage 拉全帖图集（Android PhotoViewViewModel.Init 对齐；
    /// 失败/空结果回退 initialItems——Android Init.Failure 同款降级）
    static func resolveGallery(initialItems: [PicViewItem], initialIndex: Int,
                               context: PicPageContext?) async -> (items: [PicViewItem], index: Int) {
        let safeIndex = min(max(0, initialIndex), max(0, initialItems.count - 1))
        guard let ctx = context, let anchor = initialItems.last else {
            return (initialItems, safeIndex)
        }
        do {
            let resp = try await TiebaWriteEndpoints.picPage(
                forumId: ctx.forumId, forumName: ctx.forumName, threadId: ctx.threadId,
                picId: anchor.id, picIndex: safeIndex + 1, objType: ctx.objType,
                seeLz: ctx.seeLz, prev: false)
            var server: [PicViewItem] = []
            var seen = Set<String>()
            for pic in resp.pic_list ?? [] {
                let info = pic.img?.original
                let origin = info?.original_src ?? info?.big_cdn_src ?? ""
                let show = info?.big_cdn_src ?? origin
                guard !show.isEmpty, !origin.isEmpty else { continue }
                let id = info?.id ?? tiebaPicId(from: origin)
                guard seen.insert(id).inserted else { continue }
                server.append(PicViewItem(id: id, url: show, originUrl: origin))
            }
            if !server.isEmpty {
                // 锚点不在服务端列表时补回，保证初始定位语义
                if !server.contains(where: { $0.id == anchor.id }) {
                    server.insert(anchor, at: min(max(0, safeIndex), server.count))
                }
                let idx = server.firstIndex(where: { $0.id == anchor.id }) ?? safeIndex
                return (server, idx)
            }
        } catch {
            // 静默降级（Android Init.Failure 同款）
        }
        return (initialItems, safeIndex)
    }
}

/// UIViewControllerRepresentable 壳：SKPhotoBrowser 本体即封面根 VC，
/// 其内置关闭按钮直接结束 fullScreenCover
struct SKPhotoBrowserView: UIViewControllerRepresentable {
    let photos: [PicViewItem]
    let initialIndex: Int

    func makeUIViewController(context: Context) -> SKPhotoBrowser {
        let skPhotos = photos.map { item -> SKPhoto in
            let p = SKPhoto.photoWithImageURL(item.url)
            p.shouldCachePhotoURLImage = true
            return p
        }
        let browser = SKPhotoBrowser(
            photos: skPhotos,
            initialPageIndex: min(max(0, initialIndex), max(0, skPhotos.count - 1)))
        // 保存/分享走浏览器内置长按菜单与 action 按钮（成熟库能力，不自研）
        browser.initializePageIndex(browser.currentPageIndex)
        return browser
    }

    func updateUIViewController(_ uiViewController: SKPhotoBrowser, context: Context) {}
}
