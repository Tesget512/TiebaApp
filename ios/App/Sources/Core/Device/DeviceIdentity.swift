import Foundation
import CryptoKit

/// 设备标识：复刻 Android 端 UIDUtil / CuidUtils 的取值逻辑。
///
/// iOS 与 Android 的平台差异及对应策略（字段格式必须与 Android 一致，服务端才认）：
/// - `androidId`：Android 取 Settings.Secure.ANDROID_ID（16 位 hex）；iOS 首启生成随机
///   16 位 hex 持久化（Keychain/UserDefaults），语义等价（稳定设备标识）。
/// - `imei`：Android 10+ 取不到，统一用 "000000000000000"；iOS 同样固定该值。
/// - `uuid`：随机 UUID，持久化（对应 Android SP 里的 uuid）。
///
/// 字段对应关系（Android 端调用点）：
/// - `cUID`   = MD5("com.baidu" + androidId).uppercase()          —— CuidUtils/UIDUtil
/// - `newCUID`= "$cUID|V" + Base32(heliosHash(cUID))              —— CuidUtils.getNewCuid
/// - `c3_aid` = "A00-" + Base32(SHA1("com.helios"+androidId+uuid)) + "-" + Base32(heliosHash(...))
/// - `finalCUID` = cUID + "|" + imei.reversed()
struct DeviceIdentity {
    let androidId: String
    let uuid: String

    private let imei = "000000000000000" // Android 10+ 同样拿不到 IMEI

    init() {
        let defaults = UserDefaults.standard
        var aid = defaults.string(forKey: "tieba.androidId")
        if aid == nil {
            aid = String(format: "%016x", UInt64.random(in: 0..<UInt64.max))
            defaults.set(aid, forKey: "tieba.androidId")
        }
        androidId = aid!
        var u = defaults.string(forKey: "tieba.uuid")
        if u == nil {
            u = UUID().uuidString
            defaults.set(u, forKey: "tieba.uuid")
        }
        uuid = u!
    }

    var cUID: String {
        md5Hex("com.baidu\(androidId)").uppercased()
    }

    var newCUID: String {
        "\(cUID)|V\(Base32.encode(HeliosHasher.hash(Array(cUID.utf8))))"
    }

    var finalCUID: String {
        "\(cUID)|\(String(imei.reversed()))"
    }

    /// "A00-" + Base32(SHA1("com.helios"+androidId+uuid)) + "-" + Base32(heliosHash(rawAid))
    var c3Aid: String {
        let encoded = Base32.encode(sha1("com.helios\(androidId)\(uuid)"))
        let rawAid = "A00-\(encoded)-"
        let sign = Base32.encode(HeliosHasher.hash(Array(rawAid.utf8)))
        return "\(rawAid)\(sign)"
    }

    private func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Array(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sha1(_ s: String) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: Array(s.utf8)))
    }
}
