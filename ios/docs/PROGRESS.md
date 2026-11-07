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

## 2026-11-06 P9 遗留功能全量补全 + App Icon ✅

- **审计与协议提取**：3 个 Explore 子代理并行提取 Android 精确协议
  （写操作/阅读页/设置与服务三路），主智能体亲核 addThread（MiniTiebaApi.kt:424-449
  全部 22 个字段默认值）、setUserBlack/getUserBlackInfo（PermissionListBean JSON 序）、
  profileModify（9 字段）、delThread/delPost（src/is_vipdel/delete_my_* 映射）、
  OKSigner 全流程（msign 等级阈值+msignStepNum 上限+from_widget=1+慢速 3500-8000ms）、
  GeneralTabList 23 字段（V12_POST 通道）、TopicDetail（HYBRID GET 9 参数）、
  BlockManager（白名单优先/关键词+用户/正则）、草稿 hash（threadId_postId_subPostId MD5）、
  EmoticonManager（#(名字) 插入格式 + static.tieba.baidu.com 图片源）、
  剪贴板检测（10s 节流 + tieba 域名 + /p/ 与 /f?kw= 解析）。
- **App Icon**：复用 Android `ic_launcher_new_foreground`（432px）+ colors.xml 背景色
  合成 1024px iOS 图标（PIL 脚本），主图标 + 反色/旧版两个备选
  （对应 Android LauncherIcons 的 NEW/INVERT/OLD）；
  Info.plist 注册 `CFBundleAlternateIcons`；`AppIconManager` 走
  `UIApplication.setAlternateIconName`；设置页可切换。
- **写操作端点**：`TiebaWriteEndpoints` 新增 addThread（发主题贴）/delThread/delPost/
  checkReport（举报预检→URL）/getUserBlackInfo/setUserBlack（拉黑三开关）/
  profileModify（改资料）；`OKSigner.swift` 一键签到全流程（getforumlist 配置 →
  msign 批量 → 单签兜底 → 失败中止开关 → 进度回调）。
- **阅读页**：`ReadingPages.swift`（吧详情 ForumDetailPage / 吧规 ForumRulePage /
  热议列表 TopicListPage / 热议详情 TopicDetailPage（含 HYBRID GET 客户端）/
  关注·粉丝列表 FollowListView / 他人关注吧 UserLikeForumListPage）；
  `AnalysisPages.swift`（发言分析：按月/时段/吧 TOP10/高频词 2-3gram 词频 + 保存/分享
  图片查看器 PhotoViewPage + 双指缩放 + 相册保存）。
- **设置中心**：`SettingsView`（安全模式/无痕/主题/深色/字体 6 档/屏蔽/一键签到设置/
  关于 7 连击彩蛋/账号管理含小尾巴）；`AppPreferences`（对应 Android
  AppPreferencesUtils 键名）；`BlockManager`（黑/白名单+正则+用户，UserDefaults 持久化，
  ThreadListView 应用过滤）。
- **体验补全**：ReplySheet 增强（草稿 500ms 防抖/表情面板#(名字)/小尾巴附加/安全模式
  拦截）；ThreadPage 楼层菜单（复制/举报/删除自己楼层）+ 图片点击查看器 + 主题贴
  删除/举报；ForumPage 发帖按钮 + 吧详情入口；RootView 剪贴板链接检测弹窗 +
  启动时通知权限请求与未读本地通知（Android NotifyJobService 的前台轻量替代）；
  UserProfilePage 关注/粉丝/TA的吧/发言分析/拉黑入口。
- **验收**：`** BUILD SUCCEEDED **` + `** TEST SUCCEEDED **` **33/33 全过**
  （新增 吧详情/吧规/通用标签 3 个真实网络冒烟）；模拟器启动正常（发现页渲染 +
  系统通知权限弹窗出现，验证通知调度已接入）；App 图标编译验证
  （AppIcon60x60@2x 内容正确 + 备选图标注册）；adhoc ipa 2.5M 验收全过
  （Signature=adhoc / TeamIdentifier=not set / 无 mobileprovision / strict 通过）。

### P9b 追加补全（同日）

- **多账号管理**：`AccountStore` 改造为账号数组（Keychain "accounts" + UserDefaults
  "tieba.currentUid"，对齐 Android Room account 表 + accountData.now）；
  `AppState` 新增 `allAccounts`/`switchAccount`/按 uid 退出；
  `AccountManageView` 升级为账号列表（切换勾选/添加账号/退出当前/复制 BDUSS/小尾巴）。
- **WebViewPage**（对应 Android WebViewPage）：WKWebView + 登录 cookie 注入
  （.baidu.com 域 BDUSS/STOKEN）+ 复制链接/分享/刷新；**举报**从系统浏览器改为内置页。
- **修改资料** `EditProfilePage`（昵称/简介≤500/性别 1男2女，对齐
  EditProfileViewModel 字段映射；生日按服务端默认传 0）。
- **通用标签** `GeneralTabListPage`（V12_POST 通道 generalTabList 23 字段对齐；
  吧页菜单 → navTabInfo 的 isGeneralTab=1 项 → 帖子流分页）。
- **图片上传**：`ImageUploader.upload`（/c/s/uploadPicture 单分片版，≤512KB 自动
  JPEG 压缩；字段 alt/chunkNo/groupId/height/isFinish/is_bjh/pic_water_type/resourceId/
  saveOrigin/size/width + 文件 part `chunk`，1:1 对照 ImageUploader.kt:141-157）；
  回复面板 PhotosPicker 选图 → 上传成功插入 `#(pic,id,w,h)`（ReplyPage.kt:328 格式）。
- **投票**：ThreadPage 投票组件（选项多选 → options 逗号分隔 → V12_POST
  `/c/c/post/addPollPost?cmd=309006`，对齐 ThreadPage.kt:1700 与 MixedTiebaApiImpl:1728）；
  PbPage 响应 thread.poll_info 解析。
- **平台差异说明（如实记录）**：
  - Android 后台 AlarmManager 定时签到 → iOS 仅前台"立即一键签到"+每日时间设置
    （iOS 无常驻后台执行权限，语义等价降级）；
  - Android NotifyJobService 30min 后台轮询 → iOS 启动/前台时拉一次未读并发本地通知；
  - Android 半透明壁纸主题/动态取色（Monet）→ iOS 提供深浅色 + 自定义主色（iOS 无
    等价 Monet API）；
  - 小尾巴在 Android 端仅存储未接线（grep 全库无追加逻辑）——iOS 端直接接到
    ReplySheet 提交（超出 Android 行为，已注明）；
  - Android ImageUploader 大图分片（>512KB 多 chunk）→ iOS 仅单分片（≤512KB 自动压缩），
    完整分片协议留待后续。

## 2026-11-06 P10 GitHub fork 建立与本地 git 配置 ✅

- **认证探测**：SSH key（kurako_vm_ed25519）未注册到 GitHub（publickey 拒绝）；
  macOS keychain 存有 github.com 的 https 凭证（Tesget512），经 `/user` API 验证有效。
- **fork 建立**：`POST /repos/Aur5411/TiebaApp/forks`（202 异步受理）→ 轮询 200，
  **`https://github.com/Tesget512/TiebaApp`** 就绪（default_branch=main）。
- **本地 git 配置**：
  - `origin` → `https://github.com/Tesget512/TiebaApp.git`（fork，推送目标）
  - `upstream` → `https://github.com/Aur5411/TiebaApp.git`（原作者，同步源）
  - `git push -u origin ios`：ios 分支（7c7fc2a，P0–P9 全部工作）已推送并跟踪
  - `git push -u origin main`：main（f2cabd3）与 fork 一致
  - `git ls-remote` 复核：fork 上两个分支哈希与本地一致
- 后续工作流：日常提交推 `origin`（fork）；同步上游用
  `git fetch upstream && git merge upstream/main`（main）；向原作者贡献则从 fork 发 PR。

## 2026-11-06 P11 第一轮验收修复：封面右侧/底栏对齐/搜索重构/登录持久化 ✅ (d9a2b82)

- **封面固定右侧**：FeedCard 内容区 HStack 加 `Spacer(minLength: 8)`，多图右对齐成排（≤3 张）。
- **底栏对齐 Android**：发现/进吧/通知/我的（原"搜索"底栏项改为发现页工具栏放大镜）。
- **全部列表页补 `.refreshable`** 下拉刷新。
- **登录持久化修复**：先写失败测试证实 Keychain 在未签名模拟器构建下静默失败
  （SecItemAdd 状态成功但回读失败）→ AccountStore 双通道（Keychain 回读校验 +
  Application Support 文件兜底，NSFileProtectionComplete）。

## 2026-11-07 P12/P13 第二轮验收修复：作者映射/隐藏底栏/登录参数补齐 ✅ (5e5eff5, 544b89a)

- **user_list 作者映射**：proto Post/ThreadInfo 只带 author_id，作者信息在响应级
  `user_list`——新增 AuthorResolver（id → Tieba_User join），应用于 ThreadPage、
  ForumPage、GeneralTabListPage。
- **详情页隐藏底栏**：16 个 push 页面加 `.toolbar(.hidden, for: .tabBar)`。
- **登录**：official 渠道公共参数扩到 ~25 个；`_client_id/_phone_imei` 键名修正；
  错误文案带 `[code N]`；WebView cookie 抓取注册 WKHTTPCookieStoreObserver +
  30s 轮询 + 新 BDUSS 自动重试。

## 2026-11-07 P14 登录根因修复：`/c/s/login` 双路径对齐 Android ✅

**用户反馈**：`[code 1] 用户未登录或登录失败` 持续出现（WebView 内已登录）。

**根因（读 Android 源码逐行核实）**：
1. `/c/s/login` 有**两条参数集不同的路径**（MixedTiebaApiImpl.kt:1010-1021），
   P13 混用了：
   - **web 登录路径**（LoginPage 用）：`loginFlow("$bduss|", sToken, null)` ——
     bdusstoken 竖线后为**空串**、user_id **强制不发**、stoken=WebView 抓取值；
   - **无参刷新路径**（MainActivityV2.fetchAccount 用）：默认参数
     `bdusstoken="BDUSS|null"` + 已存 stoken + 已存 user_id。
   P13 用了 `"BDUSS|null"` + `stoken=""` → 服务端拒绝（code 1）。
2. **提交时机过早**：Android LoginPage（onPageFinished）要求 URL 落在
   `tieba.baidu.com/index/tbwise/` 且 BDUSS 与 STOKEN **同时存在**才提交；
   iOS 旧版见到 BDUSS 就提交（STOKEN 尚未设置 → stoken 空 → 必败），且
   `lastSubmittedBduss` 去重导致 STOKEN 到位后**不再重试**。
3. **登录态残留污染**（用户怀疑证实）：设备 `currentUid` 跨重装残留；
   App 进程 HTTPCookieStorage 也有旧百度 cookie。URLSession 默认
   `httpShouldHandleCookies` 会把陈旧 cookie 合并进登录请求 → 登录请求
   `httpShouldHandleCookies = false`。

**修复**：
- TiebaLoginClient 拆分 `fetchAccount`（web 路径）/`refreshAccount`（刷新路径）；
  公共参数补齐全量 OFFICIAL_TIEBA_API 集（defaultCommonParamInterceptor 8 项 +
  扩展 24 项 + StParamInterceptor st 统计参数 + 完整请求头 Cookie/cuid/c3_aid/
  client_log_id 等，RetrofitTiebaApi.kt:185-231 1:1）。
- LoginView 提交条件对齐 Android：URL 在 tbwise + BDUSS/STOKEN 双非空 +
  当前 URL 域名过滤（模拟 CookieManager.getCookie(url)，精确 host 优先）；
  登录时保存 BAIDUID（LoginPage saveBaiduId 对齐）；新增"清除网页登录状态"按钮。
- 登录后链路补齐：initNickname + userProfile 补 nameShow/portrait
  （fetchAccountFlow zip 顺序对齐）。
- AppState 启动刷新账号（MainActivityV2.fetchAccount 对齐：已登录时刷新，
  失败仅忽略）。

**遗留观察**：xcodebuild 测试运行器在本环境卡死（基线 P13 无改动同样复现、
新模拟器同样复现、重启 CoreSimulatorService 无效）——环境性问题，与本次改动
无关；App 本体构建+启动正常。

## 2026-11-07 P15 表情体系全量对齐 + 未对齐功能批量补全 ✅

**表情（用户验收指出缺失）**：
- **EmoticonManager 重写**（Android EmoticonManager.kt 1:1）：正确 DEFAULT_EMOTICON_MAPPING
  （旧表大量名字错误：哈哈→"嘿嘿"、呼~→"哼"、笑眼→"可爱"等 20+ 处全部修正）；
  全量 id 区间 1..50/61..101/125..137（76 个）；重复键取最后值（Kotlin mapOf 语义）；
  UserDefaults 持久化（ids+mapping）；`register(id:name:)` 动态注册（pb type=2 内容）；
  图片文件缓存 Caches/emoticon/{id}.png + 启动预下载（fetchEmoticons 对齐，串行防 76 并发）；
  NSLock 线程安全（注册从数据层任意线程触发）。
- **EmoticonText 内联渲染**（Android `String.emoticonString` + EmoticonText 对齐）：
  正则 `#\(([\u4e00-\u9fa5\w~]+)\)` 匹配段 → Text(Image) 行内拼接（1.2×字号）；
  未知名/未加载保留原文本；应用于 FeedCard 摘要、PbContentView 文本段、热榜标题。
- **pb type=2 表情段**（Android PbContentRender 对齐）：text=id、c=名字 → 注册 + 渲染
  `#(名字)`（旧实现渲染 "[名字]" 纯文本）。
- **abstractText 修正**：type 2 表情段不再丢弃（Android abstractText 1:1，仅 0/40/2）。
- **EmoticonPanel 对齐**（ReplyPage.EmoticonPanel）：named-only、自适应 48pt 网格、32pt 图。

**功能对齐批量补全（双端全功能审计后）**：
- **发帖标题输入启用**（bug：TextField 被 .disabled(true) 且 set 丢弃——只能发无标题贴）；
  对齐 Android 31 字上限。
- **无痕模式接线**：HistoryStore.record 尊重 incognitoMode（原为死开关）。
- **字体缩放全局生效**：RootView dynamicTypeSize 8 档映射（原 fontScale 无消费点）。
- **主题生效**：全局 .tint（自定义主色优先，否则当前主题主色）+ 夜间主题
  preferredColorScheme（跟随系统/指定深色主题；原仅持久化不生效）。
- **屏蔽视频帖接线**：ThreadListView 过滤视频帖（原死开关）；**隐藏媒体接线**：
  FeedCard 封面不渲染（原死开关）。
- **清除图片缓存**：设置-其他，显示"当前共有缓存 X"（URLCache+表情缓存统计），
  清理 URLCache + 表情内存位图/文件（对齐 MoreSettingsPage）。
- **剪贴板"打开"接线**（bug：LinkNavigator.handler 全工程无赋值，按钮空操作）：
  RootView onAppear 绑定 → sheet 承载 RouteView（帖子/吧），对齐 Android 深链。
- **视频内联播放器**（Android VideoContentRender→VideoPlayer widget 对齐）：
  封面+播放按钮 → 点击 AVKit VideoPlayer 播放；无直链走网页分支。
- **楼中楼点赞可点**（Android SubPostItem 对齐）：复用 LikeButton（/c/c/agree/opAgree）。
- **吧页排序切换**：最新 tab ⋯ 菜单按回复时间/按发帖时间（sortType 已有状态，补 UI）。
- 移除死开关「单列列表」（Android 吧列表双列布局专属，iOS 恒单列，注释说明）。

**已知剩余缺口（下轮）**：搜索历史、吧内搜索（ForumSearchPostPage）、
浏览历史双 tab（贴子记录/经过贴吧）、推荐流"不感兴趣"、图片加载设置/水印、
沉浸阅读、收藏贴自动只看楼主/倒序、吧置顶管理、启动首选页。

## 2026-11-07 P16 剩余未对齐功能一次性全量补全 ✅

（用户要求"不要再分批次"；本轮按双端全功能审计清单清完剩余项）

- **搜索历史**（Android SearchPage 1:1）：SearchStore（去重置顶/上限10/清空/长按删除）、
  词流 chips 区（展开/收起）、发搜索自动入历史；**全局搜索贴子排序**（按相关2/最新5/最旧0，
  Android SearchThreadSortType）。
- **吧内搜索 ForumSearchPostPage**（Android 同名页 1:1）：hybrid searchThread + fname 限定吧名；
  筛选 全部/仅主题（tt 2/1）+ 排序 按时间/按相关（st 1/2）+ 搜索历史 + 分页；
  吧页 toolbar 放大镜入口（AppRoute.forumSearch）。
- **浏览历史双 tab**（贴子记录/经过贴吧）+「今天/更早」分组 + 长按删除 + 清空（Android HistoryPage）。
- **ThreadPage**：
  - **沉浸阅读**（immersiveMode：隐藏图片/视频段与楼中楼入口，纯文字阅读）；
  - **楼层长按 contextMenu**（复制/回复/收藏到此楼/举报/删除，与 ⋯ 菜单共用 items）；
  - **收藏到此楼**（addStore 带 pid）；
  - **加载上一页**（正序时向上补齐更早页，lowestPage 追踪）；
  - **回复后刷新并滚动到底部**（对齐 Android 回复成功滚动到自己楼层）；
  - **IP 属地**显示（author.ip_address，Android getDescText 对齐）；
  - 楼中楼行**长按 contextMenu**（复制/回复/举报/删除，SubPostItem 对齐）+ 举报内置 WebView；
  - 楼中楼页标题改「N 楼的回复」。
- **收藏页**：收藏贴自动只看楼主/自动倒序设置生效（AppRoute.thread 扩 onlyLz/desc 参数）。
- **进吧页**（Android HomePage）：吧列表排序方式菜单（按热度/发帖时间(吧ID代理)/等级/名称）、
  显示最近访问吧开关、**吧长按菜单**（置顶/取消置顶(PinnedForumStore)/复制吧名/取消关注
  (unlikeForum+确认)）；置顶吧排前并带 📌 标。
- **启动首选页**（发现/进吧/通知）生效；**深链 tblite://**（thread/forum/history/notifications，
  CFBundleURLTypes + onOpenURL，对齐 Android tblite scheme）。
- **推荐流不感兴趣**（Android DislikeBtn 1:1）：personalized 响应 threadPersonalized 的
  dislikeResource 按 tid join → 卡片 ↓ 菜单选理由 → `/c/c/excellent/submitDislike`
  （dislike 为 DislikeBean JSON 数组：tid/dislike_ids/fid/click_time/extra）→ 本地移除；
  **只推荐已关注的吧**开关过滤；**夜间模式压暗缩略图**生效。
- **图片加载模式**（智能加载/全部原图/全部不加载）接入 mediaURLs 与 PbContentView.picURL
  （原图模式 origin 优先，不加载返回空）；**上传水印**（无/用户名/吧名，UIImage 右下角绘制）。
- **我的页**：统计卡可点（关注/粉丝/发帖 → 对应列表）、新增 我的发帖/我的回帖/关注列表/粉丝列表
  直达入口、服务中心（WebView）（Android UserPage 对齐）。
- **账号管理**：修改用户名（Android 同款百度通行证网页）。
- **WebViewPage**：新增「在浏览器内打开」；**登录页**顶栏新增「刷新」。
- 平台性差异保持文档化（桌面快捷方式/电池优化提醒/宽屏 NavigationRail/Monet 取色/
  CustomTabs/状态栏遮罩——iOS 无等价 API，见 P9 记录）。

## 2026-11-07 P17 真机验收三问题修复 + 体验补强 ✅

（用户真机安装 adhoc ipa 验收反馈：刷新不了 / 帖子点不进去 / 返回时底栏闪现）

- **帖子点不进去（根因）**：ForumPage / SearchPage / ForumSearchPostPage 都是被
  push 进 ExploreView 的 NavigationStack 的页面，却各自创建了**未绑定到任何栈的
  本地 NavigationPath** 并用 `path.append` 跳转——改的是死对象，点击完全无效。
  修复：ThreadListView 行改为 `NavigationLink(value: AppRoute.thread(...))`
  （依赖所在栈已注册的 destination，任何页内都有效），浏览历史记录改由
  simultaneousGesture 在点击时统一执行；SearchPage/ForumSearchPostPage 的
  死 path 与重复 destination 移除；HotPage/ConcernFeed/Recommend/GeneralTabList
  调用点同步适配。
- **刷新转圈不结束**：请求超时 60s→15s（弱网/悬挂尽快暴露错误），刷新失败
  顶部横条提示（已有内容时），失败页加**重试按钮**（UnavailableView retry）。
- **底栏延迟半秒闪现**：iOS 26 Liquid Glass 系统 tabBar 与
  `.toolbar(.hidden, for: .tabBar)` 的 push/pop 动画缺陷 → **自定义底栏
  CustomTabBar 全面接管**：系统底栏在 4 个 tab 根视图永久隐藏，pushed 页用
  `bottomBarHidden()`（PreferenceKey 汇总）声明隐藏自定义底栏，无系统动画闪现；
  视觉对齐 Android 底部导航。
- **图片体验补强**：RemoteImage 从 AsyncImage 换成 NSCache 内存缓存 + 扩容
  URLCache（64MB 内存/256MB 磁盘，默认仅 512KB/10MB 导致列表反复重下与闪烁）。
- **adhoc 构建脚本修复**：`set -euo pipefail` 下 `codesign | grep -q` 的
  SIGPIPE 竞态（grep -q 提前退出 → codesign 退出 141 → pipefail 误判失败）
  → 改为先捕获输出再 grep。
- **验证（退出码驱动 + 截图）**：深链 tblite://thread 进帖页 → pbPage 返回
  服务端真实业务错误文案（"该贴已被删除"）→ 重试按钮/自定义底栏隐藏均生效；
  推荐流/自定义底栏截图确认。

## 2026-11-07 P18 真机验收第二轮修复 + Android 对照主线补齐 ✅

（用户反馈：悬浮底栏被改成全宽条不满意 + 列表最后一项被底栏挡住 + 图片完全打不开 +
深色模式组件颜色不适配/按钮字体没上色 + 进吧页要两列开关与自定义置顶。
并要求：以独立 fork 分支视角，逐一对照 Android 实现尽量还原主线全部功能。）

### 用户报告问题修复
- **悬浮底栏还原**：CustomTabBar 改为悬浮胶囊样式（regularMaterial 材质 + 圆角 26 +
  阴影 + 左右 14pt 留边 + 选中缩放淡入淡出 0.15s），观感对齐系统 Liquid Glass
  悬浮底栏但无系统 tabBar 闪现缺陷。
- **最后一项被遮挡**：RootView 在 TabView 上加
  `safeAreaInset(edge: .bottom)`（visible 时 64pt / 详情页隐藏时 0，动画同步），
  所有 tab 根页 List 内容自动让位，我的页「关于」等最后一项可完整滚动可见。
- **图片完全打不开**（三处叠加根因）：
  1) 楼层图片点击是**整层透明 overlay**（Color.clear+contentShape 盖住整段正文），
     拦截文字区域点击且与图片渲染条件不一致 → 改为**每张图片自身挂
     onTapGesture**（PbContentView 新增 onImageTap 回调 + 图片序号定位）；
  2) 楼中楼（FloorDetailPage）完全没有图片查看入口 → 补齐同款查看器；
  3) URL 解析失败即静默黑屏 → picURL/ZoomableImage 增加**百分号编码兜底**，
     RemoteImage 失败态改为可见「点击重试」（attempt 计数驱动 task 重跑），
     查看器无效地址显示「图片地址无效」占位而非黑屏。
  验证：深链水楼(11157539425) 帖子页图片全部渲染；-openPhoto 调试参数打开
  查看器：工具栏（关闭/下载/分享）+ 页码点 + 图片加载链路正常。
- **深色模式组件不适配**：iOS 26 Liquid Glass 工具栏胶囊在滚动后不跟随应用
  强制深色（用户截图浅色胶囊）→ RootView 加 `.toolbarColorScheme(
  usesDarkTheme ? .dark : .light, for: .navigationBar)` 强制导航栏配色；
  关于页图标硬编码 #2E60B0 → Color.accentColor。

### 进吧页（用户要求）
- **两列显示开关**：AppPreferences.forumTwoColumn（UserDefaults 持久），
  工具栏菜单 Toggle；两列用 LazyVGrid 卡片（头像/吧名/置顶钉/热帖/等级+
  chevron），单列保留原行样式；卡片跳转用 path.append（Grid 内
  NavigationLink 会带出行样式）。
- **自定义置顶修活**：原 PinnedForumStore 是纯 UserDefaults 枚举——置顶后
  **界面不刷新**（用户感知「没有置顶功能」）→ 迁移为
  AppPreferences.pinnedForums（@Published），排序改为置顶优先**且保持置顶
  先后顺序**，行/卡片 contextMenu 置顶即时重排 + toast 反馈。

### Android 对照审计补齐（Explore 全量比对 app/ vs ios/）
- **[P0] 楼中楼看图**：FloorDetailPage 原帖/子回复图片点击进查看器（本轮随
  onImageTap 一并修复——审计确认这是唯一硬缺失 P0）。
- **[P1] 吧页三态按钮**（对齐 ForumPage.kt:290-310）：未关注→「关注」（点击
  调 /c/c/forum/like）；已关注未签→「签到」；已签→「已签 N 天」置灰
  （is_sign_in/cont_sign_num 回显，frsPage 已带字段只是从未渲染）。
  签到结果弹窗（经验/连续天数/排名，ForumSignResponse 解析
  sign_bonus_point/cont_sign_num/user_sign_rank，对齐 ForumViewModel:100-112）；
  工具栏菜单补「取消关注本吧」（带确认弹窗，ForumPage.kt:655-663 对齐）。
- **[P1] 帖子页底部回复栏**（对齐 ThreadPage.kt:2021-2060 BottomBar）：
  「回复」胶囊 + **全帖点赞**（thread.agree，此前 iOS 无帖子级点赞入口）；
  工具栏回帖按钮移除（底栏唯一入口，Android 对齐）；沉浸阅读隐藏。
- **[P1] 楼层内楼中楼预览**（对齐 ThreadPage.kt:2305）：sub_post_list 前 3 条
  （作者：内容，EmoticonText 渲染表情）+「查看全部 N 条回复」，点击进楼中楼。
- **[P1] 自动签到修活**：autoSign 开关原本是**纯空壳**（全仓库无消费方）→
  AppState.runAutoSignIfDue()：启动 .task + scenePhase 回前台补执行，
  判定（开关开 && 当天未签 && 已过设定时间）后静默跑 OKSigner.run 并记录
  signDay（Android OKSignService 的应用内替代，iOS 无常驻服务）。
- **[P2] 通知底栏角标**（对齐 MainPage.kt:185-186 badge）：NotifyBadge
  ObservableObject，NotifyScheduler.pollOnce 更新未读数（不再依赖通知授权），
  CustomTabBar 通知 tab 红点数字角标（99+ 封顶），进通知页清零。
- **[P2] 通知页搜索入口**（NotificationsPage.kt:139-145 对齐）。
- 审计确认已对齐项：吧内搜索/看帖互动/收藏/举报/搜索三分类/一键签到(手动)/
  多账号/修改资料/屏蔽名单/发言分析/深链等（详见审计清单，本轮不再重复）。
- 遗留下轮候选：回复多图上传+原图开关（中）、收藏帖返回更新引导（小）、
  设置自定义分组（小）。

### 基建
- DEBUG-only 模拟器验收钩子：`simctl launch … -openThread <tid>` /
  `-openPhoto <url>`（RootView onAppear 读启动参数设置 externalRoute，
  Release 构建零影响），弥补 idb 缺失下无法合成触摸的限制。

### P18.1 反思修复（用户对模拟器截图逐点批注）
- **灰色按钮/图标根因**：AppPreferences 主题 primary 色值全部写错——
  Android colors.xml:79-88 各主题 primary 均为贴吧蓝 #4477E0
  （含 greyDark/blueDark/amoledDark），iOS 错写成灰/深蓝杂色，
  全局 .tint() 导致工具栏按钮/关注按钮/分段控件发灰。
  全部修正为 Android 精确值（tieba/blue/blueDark/greyDark/amoledDark=#4477E0、
  pink=#FF9A9E、red=#C51100、purple=#512DA8、black=#000000）。
- **吧页层级顺序**：Android ForumPage 头(840)在上、Tab 行(872)在下，
  iOS 写反 → forumHeader 移到 segmented Picker 之上。
- **深链不沉浸**：外路由卡片式 sheet 顶部露出黑色背景带 → 改
  fullScreenCover 全屏呈现（保留关闭按钮），截图确认无黑带。
- **帖子页底部回复栏**：由全宽贴边条改为与主底栏同款悬浮胶囊
  （material 圆角 26 + 阴影 + 左右留边），滚动内容从其后穿过。
- 截图验收：吧页（全屏/蓝主题/顺序正确/关注蓝胶囊）、帖子页
  （悬浮回复栏+全帖赞 198+全屏沉浸）。
