import Foundation
import Flutter
import CryptoKit
import Security

/// RC166: hardware-backed ES256 proof bridge. The Secure Enclave key cannot
/// be exported. Simulator/software fallback is intentionally NOT provided.
/// This must be registered on the iOS UIScene implicit Flutter engine.
final class FableDpopNativeBridge {
    private let channel: FlutterMethodChannel
    private let keyTag = "fable.dpop.p256.v1".data(using: .utf8)!

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "fable/dpop_native_v1", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, response in
            guard let self = self else {
                response(FlutterError(code: "DPOP_UNAVAILABLE",
                    message: "Native DPoP proof unavailable", details: nil))
                return
            }
            do {
                switch call.method {
                case "sign":
                    guard let values = call.arguments as? [String: Any] else {
                        throw ProofError.invalid
                    }
                    response(try self.sign(values))
                case "clear":
                    try self.clear()
                    response(true)
                default:
                    response(FlutterMethodNotImplemented)
                }
            } catch {
                // Avoid leaking key material, token bytes, proof, URI or
                // platform-specific errors to Flutter logs.
                response(FlutterError(code: "DPOP_UNAVAILABLE",
                    message: "Native DPoP proof unavailable", details: nil))
            }
        }
    }

    private enum ProofError: Error {
        case invalid
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func keyQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom
        ]
    }

    private func obtainPrivateKey() throws -> SecKey {
        var existing: CFTypeRef?
        var query = keyQuery()
        query[kSecReturnRef] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, &existing)
        if status == errSecSuccess {
            guard let existing = existing else { throw ProofError.invalid }
            return existing as! SecKey
        }
        guard status == errSecItemNotFound else { throw ProofError.invalid }

        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage, &error
        ) else { throw ProofError.invalid }

        let privateAttrs: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: keyTag,
            kSecAttrAccessControl: control
        ]
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: privateAttrs
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        else {
            // iOS Simulator has no Secure Enclave: fail, never create a plain
            // Data/Pem/Keychain-exportable substitute under the same policy.
            throw ProofError.invalid
        }
        return key
    }

    private func encodeP1363(_ signatureDER: Data) throws -> Data {
        let bytes = Array(signatureDER)
        var offset = 0
        func readLength() throws -> Int {
            guard offset < bytes.count else { throw ProofError.invalid }
            let n = Int(bytes[offset])
            offset += 1
            if n < 128 { return n }
            if n != 0x81 || offset >= bytes.count { throw ProofError.invalid }
            let len = Int(bytes[offset])
            offset += 1
            return len
        }
        guard offset < bytes.count && bytes[offset] == 0x30 else { throw ProofError.invalid }
        offset += 1
        let total = try readLength()
        guard total == bytes.count - offset else { throw ProofError.invalid }

        func readInt() throws -> [UInt8] {
            guard offset < bytes.count && bytes[offset] == 0x02 else { throw ProofError.invalid }
            offset += 1
            let len = try readLength()
            guard len > 0 && len <= 33 && len <= bytes.count - offset
            else { throw ProofError.invalid }
            var raw = Array(bytes[offset..<(offset + len)])
            offset += len
            while raw.count > 1 && raw[0] == 0 { raw.removeFirst() }
            guard raw.count <= 32 && raw.first.map({ $0 & 0x80 == 0 }) == true
            else { throw ProofError.invalid }
            return Array(repeating: UInt8(0), count: 32 - raw.count) + raw
        }
        let r = try readInt()
        let s = try readInt()
        guard offset == bytes.count else { throw ProofError.invalid }
        return Data(r + s)
    }

    private func normalizedOrigin(_ component: URLComponents) -> String? {
        guard component.scheme?.lowercased() == "https",
              let host = component.host?.lowercased(), !host.isEmpty,
              component.user == nil, component.password == nil
        else { return nil }
        return "https://\(host):\(component.port ?? 443)"
    }

    private func sign(_ input: [String: Any]) throws -> String {
        guard let method = input["method"] as? String,
              let target = input["htu"] as? String,
              let origin = input["origin"] as? String,
              target.count >= 10, target.count <= 2048,
              method.range(of: "^[A-Z]{3,8}$", options: .regularExpression) != nil,
              let targetURL = URLComponents(string: target),
              let originURL = URLComponents(string: origin),
              normalizedOrigin(targetURL) == normalizedOrigin(originURL),
              normalizedOrigin(targetURL) != nil,
              targetURL.query == nil, targetURL.fragment == nil,
              originURL.query == nil, originURL.fragment == nil,
              originURL.path.isEmpty || originURL.path == "/"
        else { throw ProofError.invalid }
        let token = input["accessToken"] as? String
        if let token = token, token.utf8.count < 32 || token.utf8.count > 4096 {
            throw ProofError.invalid
        }

        let privateKey = try obtainPrivateKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ProofError.invalid
        }
        var error: Unmanaged<CFError>?
        guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              representation.count == 65, representation.first == 0x04 else {
            throw ProofError.invalid
        }
        let x = base64url(representation.subdata(in: 1..<33))
        let y = base64url(representation.subdata(in: 33..<65))
        let header: [String: Any] = [
            "alg": "ES256", "typ": "dpop+jwt",
            "jwk": ["kty": "EC", "crv": "P-256", "x": x, "y": y]
        ]
        var payload: [String: Any] = [
            "htm": method, "htu": target,
            "iat": Int(Date().timeIntervalSince1970),
            "jti": UUID().uuidString
        ]
        if let token = token {
            payload["ath"] = base64url(Data(SHA256.hash(data: Data(token.utf8))))
        }
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let signingInput = base64url(headerData) + "." + base64url(payloadData)

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .ecdsaSignatureMessageX962SHA256),
              let signature = SecKeyCreateSignature(
                privateKey,
                .ecdsaSignatureMessageX962SHA256,
                Data(signingInput.utf8) as CFData,
                &error
              ) as Data? else {
            throw ProofError.invalid
        }
        return signingInput + "." + base64url(try encodeP1363(signature))
    }

    private func clear() throws {
        let code = SecItemDelete(keyQuery() as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else {
            throw ProofError.invalid
        }
    }
}
