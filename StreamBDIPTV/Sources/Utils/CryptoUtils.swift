import Foundation
import CommonCrypto

enum CryptoUtils {
    /// Mirrors `com.streambd.iptv.utils.CryptoUtils.decryptJson`
    /// Decrypts Base64-encoded AES-128-CBC (PKCS#7 padded) payloads using the native key & IV from `libnative-keys.so`.
    static func decryptJson(_ encryptedBase64: String) -> String? {
        let cleaned = encryptedBase64
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let cipherData = Data(base64Encoded: cleaned),
              let keyData = AppConfig.nativeAesKey.data(using: .utf8),
              let ivData  = AppConfig.nativeAesIv.data(using: .utf8),
              keyData.count == kCCKeySizeAES128,
              ivData.count  == kCCBlockSizeAES128 else {
            return nil
        }

        let bufferSize = cipherData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = buffer.withUnsafeMutableBytes { bufferBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, cipherData.count,
                            bufferBytes.baseAddress, bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        buffer.count = numBytesDecrypted
        return String(data: buffer, encoding: .utf8)
    }

    /// Mirrors `DecryptionInterceptor`: automatically decrypts payload if it isn't raw JSON or M3U.
    static func decryptIfNeeded(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("#EXTM3U") || trimmed.hasPrefix("//") {
            return rawText
        }
        if let decrypted = decryptJson(trimmed) {
            let decTrimmed = decrypted.trimmingCharacters(in: .whitespacesAndNewlines)
            if decTrimmed.hasPrefix("{") || decTrimmed.hasPrefix("[") || decTrimmed.hasPrefix("#EXTM3U") || decTrimmed.hasPrefix("http") {
                return decrypted
            }
        }
        return rawText
    }
}
