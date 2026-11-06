# AGENTS.md — TiebaApp (TiebaLite Fork)

> 本文件记录**已确认的长期项目事实**与用户约束。跨平台构建与发布流程、用户反复纠正的
> 重要约束都写在这里。禁止写入秘密、凭证、一次性日志、临时状态或未确认推断。

## 用户核心约束（任务纪律）

1. 需要互联网资料时**直接拉取到本地**，不要凭记忆/幻觉做事；指令无法完成时能感知并
   及时取消换路，多次无果**立即停下向用户说明**，绝不死锁。
2. 执行前确保操作有**客观事实依据**（读源码、跑真实工具、查官方文档）。
3. 阶段完成必须记录到 `ios/docs/PROGRESS.md`。
4. 适合并行的调研/审查/长构建用子智能体，但主智能体必须**亲自复核**其结论。

## 环境事实（本机 Intel Mac，已验证）

- macOS 26.7.2 (x86_64)，Xcode 26.6 + iOS SDK 26.5，Swift 6.3.3。
- **Homebrew 处于 Intel tier3，几乎全部要源码编译，速度极慢 → 不要用 homebrew 装工具**；
  一律用 GitHub 官方预编译产物（如 protoc release zip）或 `swift build` 源码构建。
- **大陆网络：优先走 Clash 代理 `http://127.0.0.1:7890`**（`curl -x http://127.0.0.1:7890 …`）。
  直连 GitHub 可通但慢，大文件必须走代理。
- 无 JDK；如需运行 Java 生成测试向量，用 Temurin 17 x64 mac tarball（脚本放在
  `ios/scripts/bootstrap_tools.sh`，下载物一律放独立目录）。
- git 身份：Tesget512 / 55989593+Tesget512@users.noreply.github.com。

## 仓库事实

- 本仓库是 TiebaLite（百度贴吧第三方客户端）的 fork：`main` = 纯 Android（Kotlin+Compose+
  Retrofit+Wire protobuf+OkHttp），**没有任何 iOS 代码**；`ios` 分支 = 新增 `ios/` 原生
  SwiftUI 应用，Android 代码保持不动。
- 包名：Android `com.huanchengfly.tieba.post`（applicationId `com.tieba`）；iOS bundle id
  采用 `com.tieba.ioslite`（与 Android applicationId 区分）。

## 贴吧协议关键事实（已逐行核对源码，勿凭记忆修改）

- **签名**：`sign = MD5(参数名排序后 name=value 无分隔符拼接 + "tiebaclient!!!")`。
  - protobuf V12/V12_POST/V22 请求的 multipart **不含 `_client_version` part** → 这类请求**不加 sign**；
  - JSON/Form 请求含 `_client_version` → 必加 sign（form 最后一个字段）。
- **multipart**：boundary 固定 `--------7da3d81520810*`；part 顺序 `stoken?` → `data`
  （filename=`file`）；part 一律不带 Content-Type。
- **API 端点→客户端实例映射**见 `ios/docs/IOS_PLAN.md §2`（V12 读接口、V22 楼中楼、
  POST 发帖、JSON login/sign/opAgree 等）。
- **登录**：WKWebView wappass → 抓 BDUSS/STOKEN → `/c/s/login` 换 uid/tbs。
- **设备指纹**：`utils/helios/*`（40bit BitSet 滚动哈希链）必须以 JDK 跑出的**真实 Java
  输出**为测试基准，iOS 实现在 `ios/App/Sources/Core/Device/`。

## iOS 工程约定

- Xcode 项目由 `ios/scripts/gen_project.py` 生成（objectVersion 54 显式格式，
  Xcode 16+ synchronized groups 手写不可行）：源文件增删后重跑，**生成后必须清
  DerivedData**（增量构建不感知文件集变化）。
- SwiftProtobuf **不用 SPM**（Xcode 26 下 local package 模块解析不可靠）：1.28.2 运行时
  源码编入静态库 target `SwiftProtobufCore`，设 `PRODUCT_MODULE_NAME=SwiftProtobuf`，
  proto 生成物用同版本 protoc-gen-swift 生成并原样 `import SwiftProtobuf`。
- 部署目标 iOS 16.0（不用 iOS 17+ API，如 ContentUnavailableView）；真机 arm64 +
  Intel 模拟器 x86_64。
- **adhoc ipa 流程**：Xcode 26 SDK 禁止直接 adhoc 构建（"Ad Hoc code signing is not
  allowed"），须 `CODE_SIGNING_ALLOWED=NO` 构建 + `codesign --sign -` 手动签名。
  一键脚本 `ios/scripts/build_ipa.sh` → `build/TiebaLite-adhoc.ipa`。
- proto 重新生成：`ios/scripts/generate_protos.sh`（protoc-gen-swift 1.28.2 +
  dedup 同名文件 + 删除多余 import），产物不手改。

## 阶段进度

进度与阶段记录见 `ios/docs/PROGRESS.md`（每完成一阶段更新一次）。
