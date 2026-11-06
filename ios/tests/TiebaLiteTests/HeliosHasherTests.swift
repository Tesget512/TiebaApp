import XCTest
@testable import TiebaLite

/// helios 哈希对照测试：基准来自 HasherVector.java（真实 JDK 17 运行 Android 同源 Java 源码的输出）。
/// 若本测试失败，说明 Swift 移植与 Android 端不一致，必须修复移植而不是改向量。
final class HeliosHasherTests: XCTestCase {

    // 向量生成命令（在 ios/tests/java 下）：
    //   javac com/huanchengfly/tieba/post/utils/helios/*.java && java com.huanchengfly.tieba.post.utils.helios.HasherVector
    private static let vectors: [(input: String, expect: String)] = [
        ("hello", "6846e14b4f"),
        ("com.baidu0123456789abcdef", "8f7a53599f"),
        ("C0FFEE1234567890ABCDEF1234567890", "505329fa36"),
        ("A00-ABCDEFGHIJKLMNOPQRSTUVWXYZ2345678-", "84e9d150af"),
        ("a", "06d3e9df47"),
        ("0123456789abcdef", "165187a7df"),
    ]

    func testHashMatchesJavaVectors() {
        for (input, expect) in Self.vectors {
            let got = HeliosHasher.hash(Array(input.utf8))
                .map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(got, expect, "输入 \"\(input)\" 与 Java 输出不一致")
        }
    }

    func testBinaryInputMatchesJavaVector() {
        var bin = [UInt8]()
        for i in 0..<20 { bin.append(UInt8(i)) }
        let got = HeliosHasher.hash(bin).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(got, "c44faa063e")
    }

    func testBase32MatchesKnownEncoding() {
        // 5 字节 -> 8 字符完整编码
        XCTAssertEqual(Base32.encode([0x66, 0x6F, 0x6F, 0x62, 0x61]), "MZXW6YTB")
        // 不足 5 字节：按 Java 逻辑裁剪尾部（1 字节 -> 2 字符）
        XCTAssertEqual(Base32.encode([0x66]), "MY")
    }

    func testCuidFormat() {
        // 只验证格式与确定性，不断言具体值（依赖持久化的随机 androidId/uuid）
        let id = DeviceIdentity()
        XCTAssertEqual(id.androidId.count, 16)
        XCTAssertTrue(id.cUID.range(of: "^[0-9A-F]{32}$", options: .regularExpression) != nil)
        XCTAssertTrue(id.newCUID.contains("|V"))
        XCTAssertTrue(id.c3Aid.hasPrefix("A00-"))
        // Android getAid(): rawAid = "A00-{base32(sha1)}-" 后接 helios sign（无分隔符）
        XCTAssertTrue(id.c3Aid.range(of: "^A00-[A-Z2-7]+-[A-Z2-7]+$", options: .regularExpression) != nil)
        // 幂等
        XCTAssertEqual(id.newCUID, DeviceIdentity().newCUID)
    }
}
