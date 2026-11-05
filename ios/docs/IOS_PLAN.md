# iOS 分支计划书（IOS_PLAN.md）

> 本文档是 iOS 分支的**总计划书**，用于防止任务偏离。任何阶段开始前先对照本计划；
> 阶段完成后在 `ios/docs/PROGRESS.md` 记录。长期有效的项目事实写入仓库根 `AGENTS.md`。

## 0. 任务目标（用户原文）

- `git clone https://github.com/Aur5411/TiebaApp`，制作 **iOS 分支**
- 目标：完成整个 iOS 分支的制作，并能构建出**仅供安装、仅含 adhoc 签名（不含其他签名）的 ipa 包**

## 1. 环境事实（已验证）

| 事实 | 结论 |
|---|---|
| 本机 | Intel Mac (x86_64)，macOS 26.7.2 |
| Xcode | 26.6 (17F113)，iOS SDK 26.5 — 可直接构建 |
| Swift | 6.3.3（Swift 6 编译器，可用 Swift 5 语言模式） |
| protoc / JDK / swiftlint | 均未安装，需自行获取 |
| Homebrew | Intel Mac tier 3，源码编译极慢 → **禁用 homebrew，全部工具走 GitHub 预编译产物或源码构建** |
| 网络 | 大陆直连 GitHub 可通但部分资源慢；Clash 代理 `http://127.0.0.1:7890` 可用。**大文件/慢资源一律走代理** |
| Java | 无 JVM → 下载 Temurin 17 (x64 mac) 用于运行 Android 端 helios 算法生成**真实测试向量** |

## 2. 源项目关键事实（已逐一亲核源码，非转述）

- 项目：TiebaLite（百度贴吧第三方客户端），Kotlin 2 + Jetpack Compose + Retrofit + Wire(protobuf) + OkHttp + Hilt + Room。**纯 Android，无任何现成 iOS 代码**，405 个 .kt + 106 个 .java。
- **签名算法**（`api/retrofit/interceptors/SortAndSignInterceptor.kt`）：
  `sign = MD5(参数按名字排序后 name=value 无分隔符拼接 + "tiebaclient!!!")`
  - Query 分支：URL 带 `BDUSS` 且无 sign 时，query 段排序后**无分隔符**拼接计算，sign 追加到 query
  - FormBody 分支：body 含 `_client_version` 时计算，sign 追加为最后一个 form 字段
  - Multipart 分支：非文件 part 按 name 排序 `name=readString()` 无分隔符拼接；文件 part 按文件名排序放最后
- **multipart 信封**（`api/ProtobufRequest.kt:26-46` + `api/retrofit/body/MyMultipartBody.kt`）：
  - boundary 固定 `--------7da3d81520810*`，Content-Type: `multipart/form-data; boundary=...`
  - V12/V12_POST/V22 请求体**不含** `_client_version` part（放在 protobuf CommonRequest 里）→ **这类请求不加 sign**
  - part 顺序：`stoken`（已登录时）→ `data`（filename="file"，protobuf 字节）；所有 part 均无 Content-Type
- **API 实例映射**（`RetrofitTiebaApi.kt` + `MixedTiebaApiImpl.kt` 已核对）：
  - `OFFICIAL_PROTOBUF_TIEBA_V12_API`（`https://tiebac.baidu.com`，UA=`tieba/12.52.1.0`）：personalized、frsPage、threadList、userProfile、pbPage、searchSug、getForumDetail、userPost 等**全部核心读接口**
  - `OFFICIAL_PROTOBUF_TIEBA_API`（带 query 公共参数 + 会签名）：userLike、hotThreadList、topicList、forumRecommend、forumGuide
  - `OFFICIAL_PROTOBUF_TIEBA_V22_API`（`tieba/22.10.1.0`）：**pbFloor（楼中楼）**
  - `OFFICIAL_PROTOBUF_TIEBA_POST_API`（`tieba/12.35.1.0`，tbs）：generalTabList、addPost（发帖/回帖）
  - `OFFICIAL_TIEBA_API`（JSON，form sign）：login、initNickname、sync、sign、mSign、getForumList、follow/fans、threadStore、pb/floor(JSON)
  - `MINI_TIEBA_API`（JSON 7.2.0.0，`from=1021636m`，`subapp_type=mini`）：opAgree（点赞）、forumPage(JSON版)、searchPost、userLikeForum
  - `NEW_TIEBA_API`（JSON 8.2.2）：replyMe/atMe/agreeMe 通知
- **登录**：无密码/OAuth API。WKWebView 打开 `https://wappass.baidu.com/passport?login&u=...`，登录完成后从 cookie 抓 `BDUSS/STOKEN`，再调 `/c/s/login`（`bdusstoken=BDUSS|null`）取 uid/name/portrait/**tbs**（写操作令牌）。
- **设备指纹**（需逐行翻译）：`utils/UIDUtil.kt`、`utils/CuidUtils.kt`、`utils/helios/*`（Java BitSet 语义的 40bit 滚动哈希链：CRC32+xxHash32×2+CRC32，其中存在依赖 BitSet 位长截断语义的边界行为，**必须用真实 Java 输出做对照测试**）。
  - iOS 侧 `androidId` 用首启随机 16 位 hex 持久化替代；`imei` 用 `000000000000000`（Android 10+ 同样拿不到）
- **proto**：211 个 proto3 文件，package `tieba`/`tieba.xxx`，可用 protoc + swift-protobuf 直接编译。

## 3. 总体方案

**原生 SwiftUI 重写（iOS 16.0+），共享 Android 端的 protobuf schema 与协议实现，不引入跨平台框架。**

理由：
1. Android 端 106 个 Java 文件 + AndroidX/Hilt/Glide 全家桶无法参与 iOS 编译，KMP 改造 ≈ 全部重写；
2. 网络层是纯 HTTP + proto3 + MD5，任何栈都能 1:1 复刻，移植风险集中在**协议细节**而非语言；
3. SwiftUI 可在本机 Xcode 直接构建出 ipa，满足「仅 adhoc 签名」目标。

### 3.1 目录规划（ios/）

```
ios/
  TiebaLite.xcodeproj/          # 手写 pbxproj（Xcode 16 synchronized groups 格式，objectVersion 77）
  App/                          # App 同步组（Swift 源码自动纳入编译）
    Sources/…                   # App / Features / Core(API,Proto,Device,Models)
    Resources/…                 # Assets.xcassets 等
  Generated/Protos/             # protoc 生成物（脚本产出，不手改）
  ThirdParty/SwiftProtobuf/     # 浅克隆官方仓库（本地 SPM 包，离线可用）
  scripts/
    bootstrap_tools.sh          # 下载 protoc / JDK、构建 protoc-gen-swift（走代理）
    generate_protos.sh          # proto → Swift 生成
    build_ipa.sh                # 构建 .app → adhoc 签名 → Payload → ipa
  docs/                         # 本计划书、进度记录、移植笔记
  Tests/                        # helios 等算法的对照测试（用 Java 真实输出做断言）
```

### 3.2 阶段划分

| # | 阶段 | 产出 | 验收标准 |
|---|---|---|---|
| P0 | 计划书 + 分支 | 本文件、AGENTS.md、`ios` 分支 | 文档齐备，分支就位 |
| P1 | 工具链 | protoc、protoc-gen-swift、JDK17 | 三个工具可执行 |
| P2 | proto 生成 | `ios/Generated/Protos/*.swift` | swiftc 语法通过（随骨架一起编译） |
| P3 | 项目骨架 | TiebaLite.xcodeproj + 空壳 App | 模拟器可运行 |
| P4 | 协议层 | Device 指纹（helios 翻译 + Java 对照测试）、签名、multipart、CommonRequest、登录 | 对照测试全绿；抓包级参数与 Android 端一致（按代码比对） |
| P5 | UI 层 | 发现/吧/帖子/楼中楼/用户页/搜索/登录/我的/设置(简) | 模拟器真数据浏览 |
| P6 | 构建产物 | `build_ipa.sh` + ipa | ipa 仅含 adhoc 签名（codesign -dv 验证、无 embedded.mobileprovision），可安装 |
| P7 | 收尾 | README、AGENTS.md 更新、提交 | 文档与提交完整 |

### 3.3 iOS 版功能范围（v1）

- ✅ 发现（个性化推荐 personalized，proto）、热议热帖（hotThreadList）、进吧推荐（forumRecommend）
- ✅ 吧页（frs/page）、帖子列表（threadlist）、帖子内容（pb/page）、楼中楼（pb/floor）
- ✅ 用户主页（userProfile）、用户帖子（userpost）
- ✅ 搜索（searchSug + 网页搜索接口）
- ✅ 登录（WKWebView + BDUSS）、账号信息、tbs 刷新
- ✅ 点赞（opAgree，MINI JSON）、吧签到（sign/msign，JSON）
- ✅ 回帖（addPost proto，如时间允许；不承诺）
- ❌ 发主题帖/投票/上传图片、管理操作、自动签到、多账号管理、历史记录持久化（列入后续迭代）

### 3.4 构建 adhoc ipa（目标产物）

```
xcodebuild -project ios/TiebaLite.xcodeproj -scheme TiebaLite -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" build
→ .app → codesign 验证 → Payload/ → zip → TiebaLite-adhoc.ipa
```
验收：`codesign -dv` 显示 `Signature=adhoc`；包内无 `embedded.mobileprovision`；无其他签名痕迹。
（adhoc 包不能直接装非越狱设备，用户可后续用自己证书重签——这正是「仅 adhoc」的用途。）

### 3.5 风险与对策

| 风险 | 对策 |
|---|---|
| 手写 pbxproj 格式错误 | 用 Xcode 16+ synchronized groups（文件自动纳管），结构极简；P3 阶段即验证 |
| helios BitSet 截断语义翻译错 | 下载 JDK 跑 Android 同源 Java 代码生成测试向量，Swift 单测对照（P4 验收） |
| swift-protobuf 本地包解析失败 | 兜底：把 SwiftProtobuf 源码做成第二个静态库 target（无需 SPM） |
| 大量 proto 生成物编译慢 | 只编译一次进 DerivedData；必要时裁剪未用 proto |
| 大陆网络慢 | 一律优先走 7890 代理；失败自动降级直连重试 |
| 死锁 | 任一方式连续 3 次失败 → 停下换路或向用户说明（用户约束 5） |
