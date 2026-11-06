# iOS 分支阶段进度记录（PROGRESS.md）

> 约束：每完成一个阶段必须在此追加一条记录（日期、做了什么、验收结果、遗留问题）。

## 2026-11-06 P0 计划书与分支建立 ✅

- 克隆 `Aur5411/TiebaApp`（main），创建 `ios` 分支。
- 调研完成（Explore 子代理 + 主代理亲核关键文件）：
  - 网络层：`RetrofitTiebaApi.kt`（10 个 API 实例与拦截器链）、`SortAndSignInterceptor.kt`
    （MD5+`tiebaclient!!!`）、`MyMultipartBody.kt`/`ProtobufRequest.kt`（multipart 信封、
    V12 无 sign）、`CommonParamInterceptor.kt`/`StParamInterceptor.kt`（multipart 非空时 st 参数不注入）。
  - 端点映射：MixedTiebaApiImpl 中 V12（读）、V22（楼中楼）、POST（发帖）、JSON（登录/签到/点赞）。
  - 设备指纹：UIDUtil/CuidUtils/helios（Java BitSet 40bit 哈希链，需 JDK 测试向量对照）。
  - 登录：wappass WebView → BDUSS/STOKEN → /c/s/login → tbs。
- 本机环境验证：Xcode 26.6/iOS SDK 26.5 可用；protoc/JDK 缺失；homebrew tier3 禁用。
- 写入 `ios/docs/IOS_PLAN.md`、`AGENTS.md`。
- 遗留：P1 工具链下载（protoc、swift-protobuf、Temurin JDK）。


## 2026-11-06 P4a 设备指纹层完成 ✅（含协议层关键修复）

- **SwiftProtobuf 运行时方案定型**：SPM 本地包在 Xcode 26 下模块解析反复失败
  （仅编译出 x86_64、incompatible target 等），按计划书兜底路线改为 **1.28.2 运行时
  源码直接编入独立静态库 target `SwiftProtobufCore`**，app target 依赖链接；
  protoc-gen-swift 同步用 1.28.2 重新生成 proto（325 文件，版本与运行时一致）。
- **helios 哈希 1:1 移植并经真实 JDK 向量验证**（7/7 全过）：
  - 过程中发现并修复 4 个移植 bug：
    1. Java `encode(bytes, 0, len)` 只处理前 len 字节（Swift 初版处理整个缓冲）
    2. `Int32(seed)` 在 -O 下陷阱崩溃 → 必须 `Int32(truncatingIfNeeded:)`（Java int 回绕语义）
    3. Java `>>>` 是逻辑右移，`Int32 >>` 是算术右移 → 雪崩阶段改用 UInt32
    4. HashResult 初始 BitSet 为 **40 位全 1** 且循环前先写 5 字节 0xFF 进 buffer
  - 向量基准：`ios/tests/HasherVector.java`（Temurin 17 运行 Android 同源源码）
- **测试基建**：pbxproj 生成器支持 TiebaLiteTests target（TEST_HOST/BUNDLE_LOADER/
  ENABLE_TESTABILITY），共享 scheme；`xcodebuild test` 4/4 通过。
- 新增：`Core/Device/HeliosHasher.swift`、`Core/Device/Base32.swift`、
  `Core/Device/DeviceIdentity.swift`（cUID/newCUID/finalCUID/c3Aid，androidId 用
  持久化随机 16hex 替代）。
- 遗留：API 客户端（签名/multipart/CommonRequest）→ P4b。

## 2026-11-06 P4b 协议层完成 ✅（真实 API 冒烟验证通过）

- **API 客户端全链路打通并在模拟器上真实调通**（NetworkSmokeTests 2/2 通过）：
  - `ProtobufEnvelope`：固定 boundary `--------7da3d81520810*` 的 multipart 信封
  - `CommonRequestBuilder`：V12 分支全部字段（含 helios 设备指纹 cUID/c3_aid）
  - `TiebaAPIClient`：headers（X-BD-Data-Type/Cookie/CUID 系）+ 错误探测（ProtoCommonResponse）
  - `TiebaEndpoints`：personalized/frsPage/pbPage/userProfile 四个核心端点
  - 真实验证：`/c/f/excellent/personalized?cmd=309264` 与 `/c/f/frs/page?cmd=301001`
    返回真实帖子/吧数据（断言非空通过）
- pbxproj 生成器关键修复：proto 文件此前未进 app Sources phase（漏 append）；
  SwiftProtobufCore 设置 PRODUCT_MODULE_NAME=SwiftProtobuf 使生成代码 import 不变
- 构建经验：pbxproj 变更后必须清 DerivedData（增量构建不感知文件集变化）
- 遗留：登录 WebView（P4c）、JSON 通道（opAgree/sign）、UI 层（P5）

## 2026-11-06 P5 核心 UI 完成 ✅（模拟器真实验收）

- **发现页渲染真实贴吧推荐流**（截图验收）：头像/用户名/吧名 chip/标题/摘要/缩略图/
  视频标记/分享·回复·点赞数全部来自真实 API（personalized cmd=309264）
- 页面清单：RootView(4 Tab)、ExploreView(发现,下拉刷新)、ForumPage(吧页,最新/精华切换)、
  ThreadPage(帖子,楼层+PbContent 富文本)、ProfileView(我的,Keychain 登录态)、
  LoginView(WKWebView 百度通行证→抓 BDUSS/STOKEN→/c/s/login 换 uid/tbs)
- 组件：FeedCard(三段式)、ThreadListView、PbContentView(type 0/1/2/3/4/5/10 富文本)、
  RemoteImage(AsyncImage)、UnavailableView(iOS16 兼容占位)
- ThreadModels 扩展：头像 URL 拼接(tb.himg.baidu.com)、相对时间、摘要提取、
  图片 URL 优先级(originPic>bigPic>srcPic)、shortNum 万位缩写
- AppState 注入 TiebaAPIClient.accountProvider（登录态进入 CommonRequest.BDUSS）
- 遗留：楼中楼详情页、搜索页、通知页(JSON 通道)、点赞/签到写操作（后续迭代）

## 2026-11-06 P6+P7 完成任务目标 ✅

- **adhoc ipa 构建成功**：`ios/build/TiebaLite-adhoc.ipa`（1.5MB，arm64 Release）
  - 关键事实：Xcode 26 SDK 直接 adhoc 构建报错 "Ad Hoc code signing is not allowed
    with SDK 'iOS 26.5'"，采用 CODE_SIGNING_ALLOWED=NO 构建 + `codesign --sign -` 手动签名
  - 验收全过：Signature=adhoc、TeamIdentifier=not set、无 embedded.mobileprovision、
    codesign --verify --strict 通过、脚本可重复执行（scripts/build_ipa.sh）
- ios/README.md：构建说明、功能状态、协议要点、测试说明
- 任务闭环：P0 计划书 → P1 工具链 → P2 proto → P3 骨架 → P4a 指纹 → P4b 协议 →
  P5 UI → P6 ipa，全部阶段记录在案

## 2026-11-06 P8 功能对齐补全 ✅（Android 主分支功能面差距审计 + 补全）

- **审计方法**：Explore 子代理产出 Android 全量功能清单（`ui/page/**` 全部屏幕、
  `api/interfaces/**` 全部端点、写操作、设置、持久化、服务/接收器、登录），
  主智能体逐行亲核 `RetrofitTiebaApi.kt` / `MiniTiebaApi.kt` / `NewTiebaApi.kt` /
  `OfficialTiebaApi.kt` / `StParamInterceptor.kt` / `CommonParamInterceptor.kt` /
  `ProtobufRequest.kt` / `SortAndSignInterceptor.kt` / `Enums.kt(HttpConstant)`。
- **关键协议发现（此前 iOS 缺失）**：热榜/关注动态/热议/进吧推荐走的
  `OFFICIAL_PROTOBUF_TIEBA_API` 通道，其 `CommonParamInterceptor` 会把
  `_client_version=12.52.1.0` 等公共参数**注入为 multipart part** → 信封含
  `_client_version` → **必须签名**（与 V12 免签通道不同）。part 顺序为
  「非文件 part 按 name 升序 → sign → data(file)」（SortAndSignInterceptor 重排逻辑）。
- **协议层补全**：
  - `ProtobufEnvelope.build` 新增 `commonParts` 参数，实现签名通道信封
  - `TiebaAPIClient` 新增 `Channel.signed` + `signedV12` + `signedChannelParts`
  - 新文件 `TiebaExtraEndpoints.swift`：hotThreadList(309661)、userLike(309474)、
    topicList(309289)、forumRecommend(303011)、userPost(303002)、historyForum(309601)、
    addPost(309731, V12_POST)
  - `TiebaWriteEndpoints` 扩展：unreadCount(`/c/s/msg`)、likeForum/unlikeForum、
    followUser/unfollowUser、addStore/removeStore、threadStore
  - `TiebaJSONClient` 补齐 Android `defaultCommonParamInterceptor` 公共参数
    （BDUSS/_client_id/_client_type/_os_version/model/net_type/_phone_imei/timestamp）
- **UI 补全**：新文件 `ExplorePages.swift`（热榜 HotPage / 关注动态 ConcernPage /
  进吧 HomeFeedPage / 收藏 ThreadStorePage / 浏览历史 HistoryPageView / 用户帖子
  UserPostListPage）；`HistoryStore`（本地浏览历史）；`AppRoute` 新增 6 个路由；
  帖子页新增「⋯」菜单（收藏/复制链接/分享/只看楼主）+ 回复面板 `ReplySheet`；
  楼中楼页支持回复；用户页新增关注/取关 + TA 的主题贴/回复入口；吧页新增分享菜单。
- **验收**：`** BUILD SUCCEEDED **` + `** TEST SUCCEEDED **`，**30/30 测试全过**
  （新增 7 个：签名通道 part 顺序、无签名回归、热榜、热议、进吧推荐、用户帖子、浏览吧；
  网络冒烟全部命中真实贴吧接口并断言实质内容）。模拟器截图验收：发现页、热榜页
  （真实 1-6 名榜单）渲染正常。
- **adhoc ipa**：`ios/build/TiebaLite-adhoc.ipa`（1.9M），验收全过
  （Signature=adhoc / TeamIdentifier=not set / 无 embedded.mobileprovision / strict 通过）。
- **遗留（未对齐 Android 的深度功能，列入后续迭代）**：
  发主题贴/投票帖/图片上传、删除主题贴/回复、举报、禁止互动（拉黑）、修改资料、
  安全模式（Android fork 特色：读-only 拦截器）、主题引擎（自定义主色/动态取色/深色模式/
  半透明壁纸）、表情面板、草稿自动保存、小尾巴、一键签到服务与定时任务、
  系统通知（NotifyJobService）、App 图标切换、剪贴板链接检测、字体大小、
  发言分析（词云统计）、关注/粉丝列表页、吧详情页（吧务/等级/会员信息）、
  吧规页、通用标签页、热议话题详情、多账号管理、webview 内嵌浏览。
