# TiebaLite iOS（ios 分支）

百度贴吧第三方客户端 TiebaLite 的 **iOS 原生实现**（SwiftUI）。与 `main` 分支的
Android 版共用同一套贴吧协议（protobuf 端点、签名算法、设备指纹），协议层 1:1 移植。

![发现页](docs/explore_screenshot.png)

## 功能状态（v2，对齐 Android 主分支功能面）

| 功能 | 状态 | 通道 |
|---|---|---|
| 发现页·个性化推荐 | ✅ 真实数据 | protobuf `/c/f/excellent/personalized`（V12） |
| 热榜 | ✅ 真实数据 | protobuf 签名通道 `/c/f/forum/hotThreadList?cmd=309661` |
| 关注动态 | ✅ 接口就绪（需登录） | protobuf 签名通道 `/c/f/concern/userlike?cmd=309474` |
| 进吧（关注吧列表） | ✅ 接口就绪（需登录） | protobuf 签名通道 `/c/f/forum/forumrecommend?cmd=303011` |
| 热议话题 | ✅ 真实数据 | protobuf 签名通道 `/c/f/recommend/topicList?cmd=309289` |
| 吧页（最新/精华+签到） | ✅ 真实数据 | protobuf `/c/f/frs/page` + JSON `/c/c/forum/sign` |
| 帖子内容·富文本 | ✅ 真实数据 | protobuf `/c/f/pb/page` |
| 楼中楼（含回复） | ✅ 真实数据 | protobuf V22 `/c/f/pb/floor` + POST `/c/c/post/add` |
| 回复/点赞/收藏 | ✅ 需登录 | POST `/c/c/post/add`、JSON `/c/c/agree/opAgree`、`/c/c/post/addstore` |
| 用户主页+关注/取关 | ✅ | protobuf `/c/u/user/profile` + JSON `/c/c/user/follow` |
| TA 的主题贴/回复 | ✅ | protobuf `/c/u/feed/userpost?cmd=303002` |
| 搜索（联想+帖子） | ✅ 真实数据 | protobuf `searchSug` + JSON `/c/s/searchpost` |
| 通知（回复/@/赞） | ✅ 需登录 | JSON NEW 通道 `/c/u/feed/replyme|atme|agreeme` |
| 浏览历史/我的收藏 | ✅ 本地+云端 | 本地 UserDefaults + JSON `/c/f/post/threadstore` |
| 登录（BDUSS） | ✅ | WKWebView wappass → `/c/s/login` |

## 构建

要求：macOS + Xcode（本工程在 Xcode 26.6 验证）+ Python 3（生成 pbxproj）。

```bash
cd ios

# 0) 一次性工具链（可选，仅重新生成 proto 时需要：protoc + protoc-gen-swift 1.28.2）
./scripts/bootstrap_tools.sh

# 1) 生成 Xcode 工程（源文件增删后重跑；proto 变更后先跑 generate_protos.sh）
python3 scripts/gen_project.py

# 2) 构建 adhoc 签名的 ipa（产物 ios/build/TiebaLite-adhoc.ipa）
./scripts/build_ipa.sh
```

产物验收：`codesign -dv` 显示 `Signature=adhoc`、`TeamIdentifier=not set`，
包内无 `embedded.mobileprovision`。**adhoc 包不能直接安装到非越狱设备**——
用你自己的证书/描述文件重签后安装（如 `codesign -f -s "iPhone Distribution: ..."` 或
AltStore/Sideloadly 等工具重签）。

## 工程结构

```
ios/
  TiebaLite.xcodeproj/        # scripts/gen_project.py 生成（勿手改）
  App/Sources/
    Core/Device/              # helios 设备指纹（1:1 移植，JDK 真实向量测试 7/7）
    Core/API/                 # 签名/multipart 信封/CommonRequest/端点/登录
    Features/                 # 发现/吧页/帖子/登录/我的
  Generated/Protos/           # protoc 生成物（勿手改；与 Android 端 proto 同源）
  ThirdParty/SwiftProtobufRuntime/  # swift-protobuf 1.28.2 源码（静态库 target）
  Tests/                      # helios 向量对照 + 真实 API 冒烟测试
  scripts/                    # 工具链下载/proto 生成/工程生成/ipa 构建
  docs/                       # 计划书（IOS_PLAN.md）与阶段记录（PROGRESS.md）
```

## 协议要点（已亲核 Android 端源码）

- **签名**：`sign = MD5(参数名排序 name=value 无分隔符拼接 + "tiebaclient!!!")`；
  V12 系列 protobuf 请求的信封不含 `_client_version` part，因此**不签名**
- **签名 protobuf 通道**（热榜/关注动态/热议/进吧推荐走的 `OFFICIAL_PROTOBUF_TIEBA_API`）：
  `CommonParamInterceptor` 会把 `_client_version=12.52.1.0` 等公共参数**注入为 multipart
  part** → 信封含 `_client_version` → **必须签名**；part 顺序变为
  「非文件 part 按 name 升序 → sign → data(file)」
- **multipart 信封**：boundary 固定 `--------7da3d81520810*`；免签通道 part 顺序
  `stoken?` → `data`
- **设备指纹**：`helios` 40-bit BitSet 哈希链（CRC32+xxHash32×2+CRC32，注意初始全 1、
  前 len 字节截断、逻辑右移三个坑），iOS 侧 androidId 用持久化随机 16hex 替代
- **登录**：wappass WebView 登录 → 抓 `BDUSS/STOKEN` → `/c/s/login` 换 uid/tbs

## 测试

```bash
xcodebuild -project TiebaLite.xcodeproj -scheme TiebaLite \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- `HeliosHasherTests`：7 个向量与 Temurin 17 运行 Android 同源 Java 的输出逐字节一致
- `ProtocolTests`：签名算法/multipart 信封 part 顺序（含签名通道）/CommonRequest 字段
- `NetworkSmokeTests`：真实调用贴吧接口（需外网），断言返回非空数据
  （发现/吧页/帖子/楼中楼/搜索/热榜/热议/进吧推荐/用户帖子/浏览吧）

## 许可

与上游 TiebaApp 相同（见仓库根 LICENSE）。仅供学习研究，勿用于生产环境；
API 协议归属百度所有。
