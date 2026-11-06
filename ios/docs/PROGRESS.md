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
