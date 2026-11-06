import Foundation

/// Base32 编码，1:1 复刻 Android `helios/Base32.kt`（注意：非标准 RFC4648——
/// 尾部不足 5 字节时按剩余字节数裁剪输出字符数）。
enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")

    static func encode(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        let blocks = (bytes.count + 4) / 5
        for i in 0..<blocks {
            var shorts = [Int](repeating: 0, count: 5)
            var i2 = 5
            for i1 in 0..<5 {
                if i * 5 + i1 < bytes.count {
                    shorts[i1] = Int(bytes[i * 5 + i1]) & 255
                } else {
                    shorts[i1] = 0
                    i2 -= 1
                }
            }
            let dt = transformInt(i2)
            let ints = [
                (shorts[0] >> 3) & 31,
                ((shorts[0] & 7) << 2) | ((shorts[1] >> 6) & 3),
                (shorts[1] >> 1) & 31,
                ((shorts[1] & 1) << 4) | ((shorts[2] >> 4) & 15),
                ((shorts[2] & 15) << 1) | ((shorts[3] >> 7) & 1),
                (shorts[3] >> 2) & 31,
                ((shorts[3] & 3) << 3) | ((shorts[4] >> 5) & 7),
                shorts[4] & 31,
            ]
            for k in 0..<(8 - dt) {
                out.append(alphabet[ints[k]].asciiValue!)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func transformInt(_ i: Int) -> Int {
        switch i {
        case 1: return 6
        case 2: return 4
        case 3: return 3
        case 4: return 1
        case 5: return 0
        default: return -1
        }
    }
}
