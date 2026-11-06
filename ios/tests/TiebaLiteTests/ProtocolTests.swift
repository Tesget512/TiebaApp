import XCTest
@testable import TiebaLite
import SwiftProtobuf

/// 协议层单测：签名、multipart 信封、CommonRequest 字段、错误探测。
/// 这些断言全部对照 Android 端源码的逐字面量核对（见各注释中的 file:line）。
final class ProtocolTests: XCTestCase {

    // MARK: - 签名（Android SortAndSignInterceptor.kt:83 calculateSign）

    func testFormSignMatchesAndroidAlgorithm() {
        // sign = MD5(参数名排序后 name=value 无分隔符拼接 + "tiebaclient!!!")
        let params: [String: String] = [
            "_client_version": "12.52.1.0",
            "kw": "李毅",
            "tbs": "abc123",
        ]
        let signed = Signer.signFormParams(params)
        // 手工构造期望值
        let raw = "_client_version=12.52.1.0kw=李毅tbs=abc123"
        let expected = Signer.md5Hex(raw + "tiebaclient!!!")
        XCTAssertEqual(signed["sign"], expected)
    }

    func testNoSignWhenClientVersionAbsent() {
        let params: [String: String] = ["kw": "李毅"]
        XCTAssertNil(Signer.signFormParams(params)["sign"])
    }

    func testMultipartSignOnlyWithClientVersion() {
        // V12/V12_POST/V22 信封不含 _client_version → 不签名
        let noVersion: [(name: String, value: String)] = [("stoken", "s")]
        XCTAssertNil(Signer.signMultipart(nonFileParts: noVersion))

        let withVersion: [(name: String, value: String)] = [
            ("_client_version", "11.10.8.6"), ("stoken", "s"),
        ]
        let sign = Signer.signMultipart(nonFileParts: withVersion)
        XCTAssertNotNil(sign)
        // 排序后 _client_version 在前
        let raw = "_client_version=11.10.8.6stoken=s"
        XCTAssertEqual(sign, Signer.md5Hex(raw + "tiebaclient!!!"))
    }

    // MARK: - multipart 信封（Android ProtobufRequest.kt:28 buildProtobufRequestBody）

    func testEnvelopeV12HasNoClientVersionPart() {
        let body = ProtobufEnvelope.build(data: Data([0x0A, 0x01]), sToken: nil)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("_client_version"), "V12 信封不应含 _client_version part")
        XCTAssertFalse(text.contains("sign"), "V12 信封不应含 sign part")
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"data\"; filename=\"file\""))
        XCTAssertTrue(text.hasPrefix("--\(ProtobufEnvelope.boundary)\r\n"))
        XCTAssertTrue(text.hasSuffix("--\(ProtobufEnvelope.boundary)--\r\n"))
    }

    func testEnvelopePartOrderStokenThenData() {
        let body = ProtobufEnvelope.build(data: Data([0xFF]), sToken: "STOKEN123")
        let text = String(decoding: body, as: UTF8.self)
        let stokenIdx = text.range(of: "name=\"stoken\"")!.lowerBound
        let dataIdx = text.range(of: "name=\"data\"")!.lowerBound
        XCTAssertLessThan(stokenIdx, dataIdx, "part 顺序必须是 stoken → data")
    }

    func testEnvelopeNoStokenWhenNilOrEmpty() {
        for token in [nil, ""] as [String?] {
            let text = String(decoding: ProtobufEnvelope.build(data: Data([0x01]), sToken: token), as: UTF8.self)
            XCTAssertFalse(text.contains("name=\"stoken\""))
        }
    }

    func testBoundaryIsFixed() {
        XCTAssertEqual(ProtobufEnvelope.boundary, "--------7da3d81520810*")
        XCTAssertEqual(ProtobufEnvelope.contentType,
                       "multipart/form-data; boundary=--------7da3d81520810*")
    }

    /// 签名通道（OFFICIAL_PROTOBUF_TIEBA_API）：commonParts 注入后信封自动签名，
    /// 且 part 顺序为「非文件 part 按 name 升序 → sign → data(file)」
    /// （Android SortAndSignInterceptor multipart 分支 + CommonParamInterceptor）
    func testEnvelopeSignedChannelPartOrder() throws {
        let body = ProtobufEnvelope.build(
            data: Data([0x0A, 0x01]), sToken: "ST",
            clientVersion: .v12,
            commonParts: [("_client_version", "12.52.1.0"), ("BDUSS", "bd"), ("kw", "李毅")])
        let text = String(decoding: body, as: UTF8.self)
        // 非文件 part 按 name 升序：BDUSS < _client_version < kw < stoken
        let bIdx = try XCTUnwrap(text.range(of: "name=\"BDUSS\"")).lowerBound
        let cvIdx = try XCTUnwrap(text.range(of: "name=\"_client_version\"")).lowerBound
        let kwIdx = try XCTUnwrap(text.range(of: "name=\"kw\"")).lowerBound
        let stIdx = try XCTUnwrap(text.range(of: "name=\"stoken\"")).lowerBound
        let signIdx = try XCTUnwrap(text.range(of: "name=\"sign\"")).lowerBound
        let dataIdx = try XCTUnwrap(text.range(of: "name=\"data\"")).lowerBound
        XCTAssertLessThan(bIdx, cvIdx)
        XCTAssertLessThan(cvIdx, kwIdx)
        XCTAssertLessThan(kwIdx, stIdx)
        XCTAssertLessThan(stIdx, signIdx)
        XCTAssertLessThan(signIdx, dataIdx)
        // 签名内容：排序后拼接（与 Android calculateSign 输入一致）
        let expected = Signer.md5Hex("BDUSS=bd_client_version=12.52.1.0kw=李毅stoken=STtiebaclient!!!")
        XCTAssertTrue(text.contains("\r\n\(expected)\r\n"), "sign part 值应为排序拼接的 MD5")
    }

    /// 无 commonParts 的 V12 信封不签名（回归保护）
    func testEnvelopeUnsignedChannelStillNoSign() {
        let body = ProtobufEnvelope.build(data: Data([0x01]), sToken: "ST",
                                          clientVersion: .v12,
                                          commonParts: [("kw", "李毅")])
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"sign\""), "无 _client_version 时不签名")
        XCTAssertFalse(text.contains("name=\"_client_version\""))
    }

    // MARK: - CommonRequest（Android ProtobufRequest.kt:103-150）

    func testV12CommonRequestConstants() {
        let r = CommonRequestBuilder.build(.v12, account: nil)
        XCTAssertEqual(r.clientVersion, "12.52.1.0")
        XCTAssertEqual(r.frameworkVer, "3340042")
        XCTAssertEqual(r.sdkVer, "2.34.0")
        XCTAssertEqual(r.swanGameVer, "1038000")
        XCTAssertEqual(r.from, "1020031h")
        XCTAssertEqual(r.clientType, 2)
        XCTAssertEqual(r.cmode, 1)
        XCTAssertEqual(r.legoLibVersion, "3.0.0")
        XCTAssertEqual(r.pversion, "1.0.3")
        XCTAssertEqual(r.netType, 1)
        XCTAssertEqual(r.isTeenager, 0)
        XCTAssertEqual(r.oaid, "")
        XCTAssertEqual(r.phoneImei, "000000000000000")
        // V12 的 android_id 是 base64 编码
        XCTAssertEqual(r.androidID, Data(DeviceIdentity.shared.androidId.utf8).base64EncodedString())
        XCTAssertFalse(r.tbs.isEmpty == false && !r.tbs.isEmpty, "V12 不设置 tbs")
    }

    func testV22CommonRequestDiffersFromV12() {
        let r = CommonRequestBuilder.build(.v22, account: nil)
        XCTAssertEqual(r.clientVersion, "22.10.1.0")
        XCTAssertEqual(r.frameworkVer, "4220001")
        XCTAssertEqual(r.sdkVer, "3.36.0")
        XCTAssertEqual(r.swanGameVer, "2035000")
    }

    func testV12PostHasTbsAndDeviceScore() {
        let acc = Account(uid: "1", name: "n", portrait: "", bduss: "b", stoken: "s",
                          tbs: "TBSVAL", zid: "", cookie: "")
        let r = CommonRequestBuilder.build(.v12Post, account: acc)
        XCTAssertEqual(r.clientVersion, "12.35.1.0")
        XCTAssertEqual(r.tbs, "TBSVAL")
        XCTAssertFalse(r.deviceScore.isEmpty)
        // V12_POST 的 android_id 不做 base64
        XCTAssertEqual(r.androidID, DeviceIdentity.shared.androidId)
    }

    func testUserAgentAppendsClientVersion() {
        let ua = CommonRequestBuilder.userAgent("tieba/12.52.1.0")
        XCTAssertTrue(ua.hasSuffix(" tieba/12.52.1.0"))
        XCTAssertEqual(CommonRequestBuilder.userAgent(nil), CommonRequestBuilder.defaultUserAgent)
    }

    // MARK: - 设备指纹（与 Android CuidUtils / UIDUtil 一致）

    func testCuidFormat() {
        let d = DeviceIdentity.shared
        XCTAssertEqual(d.cUID.count, 32, "cUID 是 MD5 十六进制串")
        XCTAssertTrue(d.cUID.allSatisfy { $0.isHexDigit })
        XCTAssertTrue(d.newCUID.hasPrefix(d.cUID + "|V"))
        XCTAssertTrue(d.c3Aid.hasPrefix("A00-"))
        let parts = d.c3Aid.split(separator: "-")
        XCTAssertEqual(parts.count, 3, "c3_aid 形如 A00-XXX-YYY")
        XCTAssertEqual(parts[0], "A00")
        XCTAssertEqual(d.finalCUID, "\(d.cUID)|000000000000000")
    }

    func testDeviceIdentityIsStable() {
        // 单例 + UserDefaults 持久化：重复读取必须一致
        XCTAssertEqual(DeviceIdentity.shared.cUID, DeviceIdentity.shared.cUID)
        XCTAssertEqual(DeviceIdentity.shared.newCUID, DeviceIdentity.shared.newCUID)
        XCTAssertEqual(DeviceIdentity.shared.c3Aid, DeviceIdentity.shared.c3Aid)
    }

    // MARK: - 错误码探测（Android ProtoFailureResponseInterceptor.kt）

    func testErrorProbeReadsErrorCode() throws {
        var err = Tieba_Error()
        err.errorCode = 340006
        err.errorMsg = "未知错误"
        var resp = Tieba_ProtoCommonResponse()
        resp.error = err
        let data = try resp.serializedData()
        let decoded = try Tieba_ProtoCommonResponse(serializedBytes: data)
        XCTAssertTrue(decoded.hasError)
        XCTAssertEqual(decoded.error.errorCode, 340006)
        XCTAssertEqual(TiebaAPIError.message(from: decoded.error), "未知错误")
    }
}
