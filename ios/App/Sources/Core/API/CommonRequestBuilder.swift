import Foundation

/// protobuf 请求的客户端版本枚举（1:1 对应 Android `api/Enums.kt` 的 ClientVersion）
enum ClientVersion: String {
    case v11 = "11.10.8.6"
    case v12 = "12.52.1.0"
    case v12Post = "12.35.1.0"
    case v22 = "22.10.1.0"
}

/// CommonRequest 构造：1:1 复刻 Android `buildCommonRequest`（`api/ProtobufRequest.kt:70`）。
///
/// 三个分支的差异（已逐行核对源码）：
/// | 字段 | V11 | V12 | V12_POST | V22 |
/// |---|---|---|---|---|
/// | framework_ver | 3340042 | 3340042 | 3340042 | **4220001** |
/// | sdk_ver | 2.34.0 | 2.34.0 | 2.34.0 | **3.36.0** |
/// | swan_game_ver | 1038000 | 1038000 | 1038000 | **2035000** |
/// | from | 1024324o | 1020031h | 1020031h | 1020031h |
/// | oaid | OAID json | "" | encodedOAID | "" |
/// | tbs | – | – | **有** | – |
/// | android_id | – | base64 | **不 base64** | base64 |
enum CommonRequestBuilder {

    /// 取 Android `RetrofitTiebaApi.initTime`：进程启动毫秒时间戳（CLIENT_LOG_ID header 用）
    static let initTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    /// 固定 UA 前缀（Android `api/Utils.kt` 的 defaultUserAgent）
    static let defaultUserAgent =
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Version/4.0 Chrome/135.0.0.0 Mobile Safari/537.36"

    /// 1:1 对应 Android `getUserAgent(appendString)`
    static func userAgent(_ append: String? = nil) -> String {
        var result = defaultUserAgent
        if let append, !append.isEmpty {
            result += " \(append.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return result
    }

    static func build(_ clientVersion: ClientVersion, account: Account?, tbs: String? = nil) -> Tieba_CommonRequest {
        let device = DeviceIdentity.shared
        let ua = userAgent("tieba/\(clientVersion.rawValue)")
        let now = Date()

        // event_day: Android SimpleDateFormat("yyyyMdd") —— 月/日不补零
        let cal = Calendar(identifier: .gregorian)
        let eventDay = "\(cal.component(.year, from: now))\(cal.component(.month, from: now))\(cal.component(.day, from: now))"

        let encodeAndroidId = clientVersion != .v12Post
        let androidIdField = encodeAndroidId
            ? Data(device.androidId.utf8).base64EncodedString()
            : device.androidId

        let isV22 = clientVersion == .v22
        let isV12Post = clientVersion == .v12Post

        var r = Tieba_CommonRequest()
        r.bduss = account?.bduss ?? ""
        r.clientID = ClientUtils.clientId
        r.clientType = 2
        r.clientVersion = clientVersion.rawValue
        r.osVersion = "16.0"
        r.phoneImei = "000000000000000"
        r.timestamp = Int64(now.timeIntervalSince1970 * 1000)
        r.activeTimestamp = ClientUtils.activeTimestamp
        r.androidID = androidIdField
        r.brand = "Apple"
        r.c3Aid = device.c3Aid
        r.cmode = 1
        r.cuid = device.newCUID
        r.cuidGalaxy2 = device.newCUID
        r.cuidGid = ""
        r.eventDay = eventDay
        r.extra = ""
        r.firstInstallTime = ClientUtils.firstInstallTime
        r.frameworkVer = isV22 ? "4220001" : "3340042"
        r.from = isV12Post || isV22 ? "1020031h" : "1020031h"
        r.isTeenager = 0
        r.lastUpdateTime = ClientUtils.lastUpdateTime
        r.legoLibVersion = "3.0.0"
        r.model = deviceModel
        r.netType = 1
        r.oaid = isV12Post ? ClientUtils.encodedOAID : ""
        r.personalizedRecSwitch = 1
        r.pversion = "1.0.3"
        r.qType = 0
        r.sampleID = ClientUtils.sampleId
        r.scrDip = Double(UIScreenCompat.density)
        r.scrH = Int32(UIScreenCompat.height)
        r.scrW = Int32(UIScreenCompat.width)
        r.sdkVer = isV22 ? "3.36.0" : "2.34.0"
        r.startScheme = ""
        r.startType = 1
        r.stoken = account?.stoken ?? ""
        r.swanGameVer = isV22 ? "2035000" : "1038000"
        r.userAgent = ua
        r.zID = account?.zid ?? ""
        if isV12Post {
            r.applist = ""
            r.deviceScore = "\(DeviceScore.value)"
            r.tbs = tbs ?? account?.tbs ?? ""
        }
        return r
    }

    /// 便捷：V12 读接口
    static func buildV12(account: Account?) -> Tieba_CommonRequest {
        build(.v12, account: account)
    }

    static var deviceModel: String { DeviceIdentity.shared.deviceModel }
}

/// 与 Android `ClientUtils` 对应的持久化客户端参数（DataStore → UserDefaults）
enum ClientUtils {
    private static let d = UserDefaults.standard

    /// `_client_id`：Android 兜底 `wappc_{initTime}_{0-999随机}`，由 `/c/s/sync` 更新
    static var clientId: String {
        if let v = d.string(forKey: "tieba.clientId") { return v }
        let v = "wappc_\(CommonRequestBuilder.initTime)_\(Int.random(in: 0...999))"
        d.set(v, forKey: "tieba.clientId")
        return v
    }

    static func setClientId(_ v: String) { d.set(v, forKey: "tieba.clientId") }

    /// `active_timestamp`：Android `ClientUtils.activeTimestamp`（毫秒时间戳）
    static var activeTimestamp: Int64 {
        if let v = d.object(forKey: "tieba.activeTimestamp") as? Int64 { return v }
        let v = Int64(Date().timeIntervalSince1970 * 1000)
        d.set(v, forKey: "tieba.activeTimestamp")
        return v
    }

    static func touchActiveTimestamp() { d.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "tieba.activeTimestamp") }

    /// `sample_id`：Android 从 `/c/s/sync` 获取；未取到时为空（不发送）
    static var sampleId: String { d.string(forKey: "tieba.sampleId") ?? "" }
    static func setSampleId(_ v: String) { d.set(v, forKey: "tieba.sampleId") }

    /// `first_install_time` / `last_update_time`：Android 用 PackageInfo 的安装/更新时间
    static var firstInstallTime: Int64 {
        if let v = d.object(forKey: "tieba.firstInstallTime") as? Int64 { return v }
        let v = Int64(Date().timeIntervalSince1970 * 1000)
        d.set(v, forKey: "tieba.firstInstallTime")
        return v
    }

    static var lastUpdateTime: Int64 {
        if let v = d.object(forKey: "tieba.lastUpdateTime") as? Int64 { return v }
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") != nil
            ? firstInstallTime : firstInstallTime
        d.set(v, forKey: "tieba.lastUpdateTime")
        return v
    }

    /// encodedOAID（V12_POST 分支使用；iOS 无 OAID）
    static var encodedOAID: String { d.string(forKey: "tieba.encodedOAID") ?? "" }

    /// `baiduid`：Android 从 BAIDUID cookie 取（ClientUtils.baiduId）；
    /// iOS 从登录抓取的 cookie 串解析，无则空串
    static var baiduId: String {
        if let v = d.string(forKey: "tieba.baiduId"), !v.isEmpty { return v }
        guard let cookie = TiebaJSONClient.shared.accountProvider()?.cookie else { return "" }
        for pair in cookie.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "BAIDUID" {
                let v = kv[1].trimmingCharacters(in: .whitespaces)
                d.set(v, forKey: "tieba.baiduId")
                return v
            }
        }
        return ""
    }

    /// 登录页抓到 BAIDUID 时主动保存（Android LoginPage 登录成功时 saveBaiduId 1:1）
    static func setBaiduId(_ v: String) {
        guard !v.isEmpty else { return }
        d.set(v, forKey: "tieba.baiduId")
    }
}

/// 屏幕参数（对应 Android `App.ScreenInfo`，由 BaseActivity.getDeviceDensity 填充）
enum UIScreenCompat {
    static var pixelSize: CGSize = CGSize(width: 1080, height: 2340)

    static var width: Int { max(1, Int(pixelSize.width)) }
    static var height: Int { max(1, Int(pixelSize.height)) }
    /// scr_dip = DisplayMetrics.density（浮点）
    static var density: Double { 3.0 }
}

/// 设备评分（对应 Android `DeviceUtils.getDeviceScore`，V12_POST 分支使用）
enum DeviceScore {
    static var value: Int { 100 }
}
