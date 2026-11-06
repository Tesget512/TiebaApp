import Foundation

/// CommonRequest 构造：1:1 复刻 Android `buildCommonRequest` 的 V12 分支
/// （iOS 客户端用 V12 protobuf 通道做全部核心读接口）。
///
/// 与 Android 的差异（平台限制，字段格式保持一致）：
/// - `_phone_imei`: Android 10+ 拿不到 → 固定 "000000000000000"（与 Android 行为一致）
/// - `android_id`: 用持久化随机 16hex（Base64 编码后传输，格式一致）
/// - `oaid`: 空字符串（Android 端 V12 分支也是 oaid=""）
/// - `z_id`: 未获取 sofire zid 时为 nil（读接口不依赖）
enum CommonRequestBuilder {
    static let clientVersionV12 = "12.52.1.0"

    static func buildV12(account: Account?) -> Tieba_CommonRequest {
        let device = DeviceIdentity()
        let ua = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Version/4.0 Chrome/135.0.0.0 Mobile Safari/537.36 tieba/\(clientVersionV12)"
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let eventDay = String(format: "%d%d%d", cal.component(.year, from: now),
                             cal.component(.month, from: now), cal.component(.day, from: now))
        let defaults = UserDefaults.standard
        let firstInstall = defaults.object(forKey: "tieba.firstInstallTime") as? Int64 ?? {
            let t = Int64(now.timeIntervalSince1970 * 1000)
            defaults.set(t, forKey: "tieba.firstInstallTime")
            return t
        }()
        let androidIdB64 = Data(device.androidId.utf8).base64EncodedString()

        var r = Tieba_CommonRequest()
        r.bduss = account?.bduss ?? ""
        r.clientID = clientId
        r.clientType = 2
        r.clientVersion = clientVersionV12
        r.osVersion = "16.0"
        r.phoneImei = "000000000000000"
        r.timestamp = Int64(now.timeIntervalSince1970 * 1000)
        r.activeTimestamp = activeTimestamp
        r.androidID = androidIdB64
        r.brand = "Apple"
        r.c3Aid = device.c3Aid
        r.cmode = 1
        r.cuid = device.newCUID
        r.cuidGalaxy2 = device.newCUID
        r.cuidGid = ""
        r.eventDay = eventDay
        r.extra = ""
        r.firstInstallTime = firstInstall
        r.frameworkVer = "3340042"
        r.from = "1020031h"
        r.isTeenager = 0
        r.lastUpdateTime = firstInstall
        r.legoLibVersion = "3.0.0"
        r.model = deviceModel
        r.netType = 1
        r.oaid = ""
        r.personalizedRecSwitch = 1
        r.pversion = "1.0.3"
        r.qType = 0
        r.sampleID = sampleId
        r.scrDip = Double(UIScreenCompat.scale)
        r.scrH = Int32(UIScreenCompat.height)
        r.scrW = Int32(UIScreenCompat.width)
        r.sdkVer = "2.34.0"
        r.startScheme = ""
        r.startType = 1
        r.stoken = account?.stoken ?? ""
        r.swanGameVer = "1038000"
        r.userAgent = ua
        r.zID = account?.zid ?? ""
        return r
    }

    // MARK: - 与 Android ClientUtils 对应的持久化客户端参数

    /// _client_id：Android 兜底 "wappc_{开机毫秒}_{0-999随机}"，首次从 /c/s/sync 换取
    static var clientId: String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "tieba.clientId") { return v }
        let v = "wappc_\(Int64(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0...999))"
        d.set(v, forKey: "tieba.clientId")
        return v
    }

    /// active_timestamp：首次启动时间戳（秒）
    static var activeTimestamp: Int64 {
        let d = UserDefaults.standard
        if let v = d.object(forKey: "tieba.activeTimestamp") as? Int64 { return v }
        let v = Int64(Date().timeIntervalSince1970)
        d.set(v, forKey: "tieba.activeTimestamp")
        return v
    }

    /// sample_id：Android 从 /c/s/sync 获取；iOS 用稳定伪随机 15 位数字串占位
    static var sampleId: String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "tieba.sampleId") { return v }
        let v = String(Int64.random(in: 100_000_000_000_000...999_999_999_999_999))
        d.set(v, forKey: "tieba.sampleId")
        return v
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { acc, el in
            guard let v = el.value as? Int8, v != 0 else { return }
            acc.append(Character(UnicodeScalar(UInt8(v))))
        }
    }
}

/// 屏幕参数（模拟 Android App.ScreenInfo）
enum UIScreenCompat {
    static var width: Int { 1080 }   // Android 端上报的物理像素宽
    static var height: Int { 2340 }
    static var scale: Int { 440 }    // 近似密度
}
