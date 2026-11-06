package com.huanchengfly.tieba.post.utils.helios;

public class HasherDebug {
    static IEncoder[] sEncoders = new IEncoder[]{new CRC32Encoder(8, 0), new XXHashEncoder(0, 1), new XXHashEncoder(1, 1), new CRC32Encoder(7, 1)};

    public static byte[] hash(byte[] bytes) {
        HashResult result = new HashResult();
        byte[] newBytes = ByteArrayUtils.copyArray(bytes, bytes.length + (sEncoders.length + 1) * 5);
        ByteArrayUtils.copyArray(newBytes, result.getValue(), bytes.length);
        System.out.println("init buffer: " + hex(newBytes, bytes.length + 10));
        System.out.println("init result: " + hex(result.getValue(), 5));

        for (int i = 0; i < sEncoders.length; i++) {
            IEncoder encoder = sEncoders[i];
            int len = bytes.length + (i + 1) * 5;
            EncodeResult er = encoder.encode(newBytes, 0, len);
            System.out.println("iter" + i + " len=" + len + " encVal=" + hex(er.a(), 8) + " start=" + encoder.getStart() + " flag=" + encoder.getFlag());
            result.update(er, encoder.getStart(), encoder.getLength(), encoder.getFlag());
            System.out.println("iter" + i + " result=" + hex(result.getValue(), 8));
            ByteArrayUtils.copyArray(newBytes, result.getValue(), len);
            System.out.println("iter" + i + " buffer=" + hex(newBytes, len + 5));
        }
        return java.util.Arrays.copyOf(result.getValue(), 5);
    }

    static String hex(byte[] b, int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < Math.min(n, b.length); i++) sb.append(String.format("%02x", b[i]));
        return sb.toString();
    }

    public static void main(String[] args) {
        byte[] out = hash("hello".getBytes());
        System.out.println("final: " + hex(out, 5));
    }
}
