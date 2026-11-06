import Foundation

/// helios 设备指纹哈希链的 Swift 移植。
///
/// 1:1 复刻 Android 端 `com.huanchengfly.tieba.post.utils.helios` 包：
/// - `Hasher.hash(bytes)`：4 个编码器（CRC32(8,0)、XXHash(0,1)、XXHash(1,1)、CRC32(7,1)）
///   顺序作用于一个不断增长的字节缓冲，最后截取前 5 字节。
/// - 关键语义：中间结果是一个「40 位 BitSet」，每次 update 后会把新值按**位**写回
///   （`HashResult.update` 里逐 bit 覆盖），且每次都以 `bytes.length + (i+1)*5` 长度
///   取前 len 字节喂给下一个编码器。Swift 用 UInt64 数组模拟位数组。
///
/// 测试基准：`ios/tests/HasherVector.java`（真实 JDK 输出），见 HeliosHasherTests。
/// Java 源码中的负数乘法常量（Int32 溢出乘法），以 UInt32 位模式表示。
private let NEG_2048144777 = UInt32(bitPattern: -2048144777)
private let NEG_1028477379 = UInt32(bitPattern: -1028477379)
private let NEG_1640531535 = UInt32(bitPattern: -1640531535)
private let NEG_1640531535_I = Int32(bitPattern: UInt32(bitPattern: -1640531535))

enum HeliosHasher {

    /// 与 Java `Hasher.hash(byte[])` 等价。输入为空时行为与 Java 一致地视为非法（生产路径 cuid 非空）。
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        precondition(!bytes.isEmpty, "helios: input must not be empty (matches Android ByteArrayUtils)")
        // encode 闭包第二个参数 len：Java 的 encode(bytes, off=0, len) 只处理前 len 字节
        let encoders: [(start: Int, flag: Int, encode: ([UInt8], Int) -> UInt64)] = [
            (8, 0, crc32),
            // Java XXHashEncoder.encode 统一 new XXHash()（无参 → seed=0），两个编码器相同
            (0, 1, xxhash32(seed: 0)),
            (1, 1, xxhash32(seed: 0)),
            (7, 1, crc32),
        ]

        // result: 40-bit BitSet（Java BitSet，低位在前）
        // Java HashResult 构造器: mEncodeResult.a(0, BITS, true) —— 初始 40 位全部置 1！
        var bits: [UInt64] = [(UInt64(1) << 40) - 1] // bits[0] 覆盖 bit 0..63，初始全 1
        // newBytes = bytes 后面接上 5*(n+1) 个零字节的缓冲，长度 = bytes.count + 20
        var buffer = bytes + [UInt8](repeating: 0, count: 5 * (encoders.count + 1))
        // Java: copyArray(newBytes, result.getValue(), bytes.length)（循环前）——
        // 初始 result 为 40 位全 1，其小端字节即 5 个 0xFF，写入 buffer[bytes.count..+5]
        for k in 0..<5 {
            buffer[bytes.count + k] = 0xFF
        }

        for (i, enc) in encoders.enumerated() {
            let len = bytes.count + (i + 1) * 5
            let value = enc.encode(buffer, len)
            // Java: result.update(EncodeResult(value), start, length=32, flag)
            //   var5 = result[start, start+32)（原 32 位）
            //   按 flag 与 value 做位运算，再逐位写回 result[start..]
            let old = readBits(bits, from: enc.start, length: 32)
            let merged: UInt64
            switch enc.flag {
            case 0: merged = old & value          // AND
            case 2: merged = old & ~value         // AND_NOT
            case 3: merged = old | value          // OR
            default: merged = old ^ value         // XOR (flag 1 及 default)
            }
            writeBits(&bits, from: enc.start, length: 32, value: merged)
            // Java: copyArray(newBytes, result.getValue(), len) —— 把 result 当前字节写回 buffer[len..]
            let resultBytes = toLittleEndianBytes(bits)
            for (j, b) in resultBytes.enumerated() where len + j < buffer.count {
                buffer[len + j] = b
            }
        }

        return Array(toLittleEndianBytes(bits).prefix(5))
    }

    // MARK: - BitSet 位操作（低位在前，与 java.util.BitSet 一致）

    private static func readBits(_ bits: [UInt64], from: Int, length: Int) -> UInt64 {
        var result: UInt64 = 0
        for k in 0..<length {
            let bit = (bits[(from + k) / 64] >> UInt64((from + k) % 64)) & 1
            result |= bit << UInt64(k)
        }
        return result
    }

    private static func writeBits(_ bits: inout [UInt64], from: Int, length: Int, value: UInt64) {
        for k in 0..<length {
            let idx = from + k
            let word = idx / 64, offset = UInt64(idx % 64)
            let bit = (value >> UInt64(k)) & 1
            bits[word] = (bits[word] & ~(1 << offset)) | (bit << offset)
        }
    }

    /// BitSet.toByteArray()：小端字节流（与 Java EncodeResult.a() 一致）
    private static func toLittleEndianBytes(_ bits: [UInt64]) -> [UInt8] {
        var out: [UInt8] = []
        for w in bits {
            for shift in 0..<8 {
                out.append(UInt8((w >> UInt64(shift * 8)) & 0xFF))
            }
        }
        return out
    }

    // MARK: - CRC32（zlib 多项式，与 java.util.zip.CRC32 一致）

    private static func crc32(_ data: [UInt8], _ len: Int) -> UInt64 {
        var crc: UInt32 = 0xFFFFFFFF
        for i in 0..<len {
            crc = crcTable[Int((crc ^ UInt32(data[i])) & 0xFF)] ^ (crc >> 8)
        }
        return UInt64(crc ^ 0xFFFFFFFF)
    }

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    // MARK: - XXHash32（百度魔改版，见 Android XXHash.java 逐行对照）

    /// 百度 helios 的 XXHash 变体：4 个 Int32 lane，seed 由构造参数决定。
    /// 注意这不是标准 XXH32——常量与更新顺序按 Java 源码复刻。
    private static func xxhash32(seed: Int) -> ([UInt8], Int) -> UInt64 {
        return { data, len in
            // i[0] = seed - 1640531535 - 2048144777
            // i[1] = seed - 2048144777
            // i[2] = seed
            // i[3] = seed + 1640531535
            // Java int 溢出回绕语义：Int→Int32 必须用 truncating（Java int 就是 32 位回绕）
            var v0 = Int32(truncatingIfNeeded: seed &- 1640531535 &- 2048144777)
            var v1 = Int32(truncatingIfNeeded: seed &- 2048144777)
            var v2 = Int32(truncatingIfNeeded: seed)
            var v3 = Int32(truncatingIfNeeded: seed &+ 1640531535)
            var l = 0          // 已处理总长度（Int 溢出行为与 Java 一致）
            var m = 0          // 缓冲区填充长度
            var j = [UInt8](repeating: 0, count: 16)

            // Java: update(bytes, off=0, len) —— 只处理前 len 字节
            if len > 0 {
                l = len
                var pos = 0
                let end = len
                if m + len < 16 {
                    for k in 0..<len { j[m + k] = data[pos + k] }
                    m += len
                } else {
                    var take = 0
                    if m > 0 {
                        take = 16 - m
                        for k in 0..<take { j[m + k] = data[pos + k] }
                        processBlock(&v0, &v1, &v2, &v3, j)
                        pos += take
                        take += 0
                    }
                    while pos + 16 <= end {
                        processBlock(&v0, &v1, &v2, &v3, Array(data[pos..<pos+16]))
                        pos += 16
                    }
                    if pos < end {
                        m = end - pos
                        for k in 0..<m { j[k] = data[pos + k] }
                    }
                }
            }

            // getValue()
            let h: Int32
            if l > 16 {
                h = Int32(bitPattern: UInt32(bitPattern: rotl(v0, 1)))
                    &+ Int32(bitPattern: UInt32(bitPattern: rotl(v1, 7)))
                    &+ Int32(bitPattern: UInt32(bitPattern: rotl(v2, 12)))
                    &+ Int32(bitPattern: UInt32(bitPattern: rotl(v3, 18)))
            } else {
                h = v2 &+ 374761393
            }
            // Java: var2 += var1 中 var2 = l（Int），l 与 h 相加后仍为 Int，再转 Int32 位模式
            var hh = Int32(bitPattern: UInt32(bitPattern: Int32(truncatingIfNeeded: l) &+ h))
            var k = 0
            while k + 4 <= m {
                let chunk = readInt32LE(j, at: k)
                hh = Int32(bitPattern: UInt32(bitPattern: rotl(hh &+ Int32(bitPattern: chunk &* NEG_1028477379), 17)) &* 668265263)
                k += 4
            }
            while k < m {
                hh = Int32(bitPattern: UInt32(bitPattern: rotl(Int32(j[k] & 255) &* 374761393 &+ hh, 11)) &* NEG_1640531535)
                k += 1
            }
            // Java: var1 = (var2 >>> 15 ^ var2) * -2048144777; ... >>> 为无符号逻辑右移，
            // 必须用 UInt32 做（Int32 >> 是算术移位，负数时符号扩展导致位模式错误）。
            var u = UInt32(bitPattern: hh)
            u = (u >> 15 ^ u) &* NEG_2048144777
            u = (u ^ (u >> 13)) &* NEG_1028477379
            let result = u ^ (u >> 16)
            return UInt64(result)
        }
    }

    private static func processBlock(_ v0: inout Int32, _ v1: inout Int32, _ v2: inout Int32, _ v3: inout Int32, _ block: [UInt8]) {
        v0 = Int32(bitPattern: UInt32(bitPattern: rotl(v0 &+ Int32(bitPattern: readInt32LE(block, at: 0) &* NEG_2048144777), 13)) &* NEG_1640531535)
        v1 = Int32(bitPattern: UInt32(bitPattern: rotl(v1 &+ Int32(bitPattern: readInt32LE(block, at: 4) &* NEG_2048144777), 13)) &* NEG_1640531535)
        v2 = Int32(bitPattern: UInt32(bitPattern: rotl(v2 &+ Int32(bitPattern: readInt32LE(block, at: 8) &* NEG_2048144777), 13)) &* NEG_1640531535)
        v3 = Int32(bitPattern: UInt32(bitPattern: rotl(v3 &+ Int32(bitPattern: readInt32LE(block, at: 12) &* NEG_2048144777), 13)) &* NEG_1640531535)
    }

    private static func readInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func rotl(_ value: Int32, _ bits: Int) -> Int32 {
        Int32(bitPattern: (UInt32(bitPattern: value) << bits) | (UInt32(bitPattern: value) >> (32 - bits)))
    }
}
