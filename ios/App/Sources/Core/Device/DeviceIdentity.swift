import Foundation
import CryptoKit

/// 设备标识：复刻 Android 端 UIDUtil / CuidUtils 的取值逻辑。
///
/// iOS 与 Android 的平台差异及对应策略（字段格式必须与 Android 一致，服务端才认）：
/// - `androidId`：Android 取 Settings.Secure.ANDROID_ID（16 位 hex）；iOS 首启生成随机
///   16 位 hex 持久化，语义等价（稳定设备标识）。
/// - `imei`：Android 10+ 取不到 → 统一 `"000000000000000"`；iOS 同样固定该值。
/// - `uuid`：随机 UUID，持久化（对应 Android SP 里的 uuid）。
///
/// 字段对应关系（Android 端 `CuidUtils.kt` / `UIDUtil.kt`）：
/// - `cUID`    = MD5("com.baidu" + androidId).uppercase()
/// - `newCUID` = "$cUID|V" + Base32(heliosHash(cUID))
/// - `c3Aid`   = "A00-" + Base32(SHA1("com.helios" + androidId + uuid)) + "-" + Base32(heliosHash(中间串))
/// - `finalCUID` = cUID + "|" + imei.reversed()
///
/// 单例：指纹计算（MD5/SHA1/Base32/helios）每次请求都要用，避免重复读 UserDefaults。
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    let androidId: String
    let uuid: String

    private let imei = "000000000000000" // Android 10+ 同样拿不到 IMEI

    private init() {
        let defaults = UserDefaults.standard
        if let aid = defaults.string(forKey: "tieba.androidId") {
            androidId = aid
        } else {
            let aid = String(format: "%016x", UInt64.random(in: 0..<UInt64.max))
            defaults.set(aid, forKey: "tieba.androidId")
            androidId = aid
        }
        if let u = defaults.string(forKey: "tieba.uuid") {
            uuid = u
        } else {
            let u = UUID().uuidString
            defaults.set(u, forKey: "tieba.uuid")
            uuid = u
        }
        // 缓存派生值（构造后不变）
        _cUID = DeviceIdentity.md5Hex("com.baidu\(androidId)").uppercased()
        let cuid = _cUID
        _newCUID = "\(cuid)|V\(Base32.encode(HeliosHasher.hash(Array(cuid.utf8))))"
        let encoded = Base32.encode(DeviceIdentity.sha1("com.helios\(androidId)\(uuid)"))
        let rawAid = "A00-\(encoded)-"
        _c3Aid = "\(rawAid)\(Base32.encode(HeliosHasher.hash(Array(rawAid.utf8))))"
        _deviceModel = DeviceIdentity.resolveDeviceModel()
    }

    private let _cUID: String
    private let _newCUID: String
    private let _c3Aid: String
    private let _deviceModel: String

    /// MD5("com.baidu" + androidId) 大写
    var cUID: String { _cUID }

    /// `<cUID>|V<Base32(heliosHash(cUID))>`
    var newCUID: String { _newCUID }

    /// "A00-<Base32(SHA1)>-<Base32(heliosHash)>"
    var c3Aid: String { _c3Aid }

    /// `cUID|` + imei 反转（NewTiebaApi 的 CUID header 用）
    var finalCUID: String { "\(_cUID)|\(String(imei.reversed()))" }

    /// 设备型号（对应 Android `Build.MODEL`）
    var deviceModel: String { _deviceModel }

    // MARK: - 内部

    private static func md5Hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Array(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha1(_ s: String) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: Array(s.utf8)))
    }

    /// 取机器标识（如 "MacBookPro18,3" / "iPhone15,2"）；取不到时退回 "iPhone"
    private static func resolveDeviceModel() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return "iPhone" }
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
    }
}
