package com.huanchengfly.tieba.post.utils.helios;

// 直接用 Android 端 helios 源码（本文件与 tests/java 下的拷贝保持逐字节一致）。
// 用于生成真实测试向量，供 Swift 侧 HasherTests.swift 断言。

public class HasherVector {
    public static void main(String[] args) {
        // 覆盖 Android 端实际出现的全部调用形态：
        //   Hasher.hash(cuid.toByteArray())                     (CuidUtils)
        //   Hasher.hash(rawAid.toByteArray())                   (UIDUtil.getAid)
        // 注意：空输入会抛 IllegalArgumentException（ByteArrayUtils.copyArray 拒绝空数组），
        //      这是 Android 端真实行为，Swift 侧同样必须复刻（cuid 永不为空，故生产路径不触发）。
        String[] inputs = {
            "hello",
            "com.baidu" + "0123456789abcdef",
            "C0FFEE1234567890ABCDEF1234567890",
            "A00-ABCDEFGHIJKLMNOPQRSTUVWXYZ2345678-",
            "a",
            "0123456789abcdef",
        };
        for (String in : inputs) {
            byte[] out = Hasher.hash(in.getBytes());
            StringBuilder sb = new StringBuilder();
            for (byte b : out) sb.append(String.format("%02x", b));
            System.out.println(in.length() + "\t" + in + "\t" + sb);
        }
        // 二进制输入（Base32 字节流场景）
        byte[] bin = new byte[20];
        for (int i = 0; i < bin.length; i++) bin[i] = (byte) i;
        byte[] out = Hasher.hash(bin);
        StringBuilder sb = new StringBuilder();
        for (byte b : out) sb.append(String.format("%02x", b));
        System.out.println("BIN20\t00 01 02 ... 13\t" + sb);
    }
}
