package com.example.helloworld

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties.KEY_ALGORITHM_EC
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.math.BigInteger
import java.net.URI
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID

/**
 * RC166: AndroidKeyStore backed, non-exportable ES256 DPoP signing bridge.
 * No pass-through private key or generic sign(bytes) method is exposed to Dart.
 * Android API >= 23. Rejects software-backed keys for strict hardware policy.
 * Hardware availability differs by device; unavailable means fail closed.
 */
internal class FableDpopNativeBridge(messenger: BinaryMessenger) {
    companion object {
        private const val CHANNEL = "fable/dpop_native_v1"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val secureRandom = SecureRandom()

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "sign" -> result.success(sign(call))
                    "clear" -> {
                        val origin = call.argument<String>("origin")
                            ?: throw IllegalStateException("origin")
                        clear(origin)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Never leak token, target, key, or signature in an exception.
                result.error("DPOP_UNAVAILABLE", "Native DPoP proof unavailable", null)
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    // Avoid correlating the same public key across different Fable origins.
    private fun alias(origin: String): String {
        val parsed = URI(origin)
        if (parsed.scheme != "https" || parsed.host.isNullOrBlank() ||
            parsed.rawQuery != null || parsed.rawFragment != null ||
            parsed.userInfo != null || parsed.path !in setOf("", "/")) {
            throw IllegalStateException("origin")
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(origin.toByteArray(StandardCharsets.US_ASCII))
        return "fable.dpop.p256." + b64(digest).take(32)
    }

    private fun getOrCreate(origin: String): java.security.KeyPair {
        val keyAlias = alias(origin)
        val store = keyStore()
        val existing = store.getEntry(keyAlias, null) as? KeyStore.PrivateKeyEntry
        if (existing != null) {
            val public = existing.certificate.publicKey as? ECPublicKey
                ?: throw IllegalStateException("key")
            ensureHardware(existing.privateKey)
            return java.security.KeyPair(public, existing.privateKey)
        }
        val generator = KeyPairGenerator.getInstance(KEY_ALGORITHM_EC, "AndroidKeyStore")
        generator.initialize(
            KeyGenParameterSpec.Builder(
                keyAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
                .build(),
            secureRandom
        )
        val pair = generator.generateKeyPair()
        ensureHardware(pair.private)
        return pair
    }

    private fun ensureHardware(privateKey: java.security.PrivateKey) {
        val factory = KeyFactory.getInstance(privateKey.algorithm, "AndroidKeyStore")
        val info = factory.getKeySpec(privateKey, KeyInfo::class.java) as KeyInfo
        if (!info.isInsideSecureHardware) {
            // Do not silently replace a missing secure element with software
            // key material. Optional StrongBox devices are supported by Keystore.
            throw IllegalStateException("hardware_key_required")
        }
    }

    private fun clear(origin: String) {
        keyStore().deleteEntry(alias(origin))
    }

    private fun b64(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE)

    private fun fixed32(value: BigInteger): String {
        val raw = value.toByteArray()
        val unsigned = if (raw.size == 33 && raw[0] == 0.toByte())
            raw.copyOfRange(1, 33) else raw
        if (unsigned.size > 32) throw IllegalStateException("coordinate")
        return b64(ByteArray(32 - unsigned.size) + unsigned)
    }

    private fun derToP1363(der: ByteArray): ByteArray {
        // Android SHA256withECDSA returns ASN.1 DER. JWS ES256 requires
        // fixed-size IEEE P1363 (R || S). Reject invalid/truncated encodings.
        var pos = 0
        fun readLen(): Int {
            if (pos >= der.size) throw IllegalStateException("der_len")
            val b = der[pos++].toInt() and 0xff
            if (b < 128) return b
            if (b != 0x81 || pos >= der.size) throw IllegalStateException("der_len")
            return der[pos++].toInt() and 0xff
        }
        if (der.isEmpty() || (der[pos++].toInt() and 0xff) != 0x30)
            throw IllegalStateException("der_sequence")
        val length = readLen()
        if (length != der.size - pos) throw IllegalStateException("der_size")
        fun integer(): ByteArray {
            if (pos >= der.size || (der[pos++].toInt() and 0xff) != 0x02)
                throw IllegalStateException("der_integer")
            val size = readLen()
            if (size == 0 || pos + size > der.size || size > 33)
                throw IllegalStateException("der_integer_size")
            val raw = der.copyOfRange(pos, pos + size)
            pos += size
            val positive = BigInteger(raw)
            if (positive.signum() < 0 || positive.bitLength() > 256)
                throw IllegalStateException("der_integer_invalid")
            val bytes = positive.toByteArray()
            val unsigned = if (bytes.size == 33 && bytes[0] == 0.toByte())
                bytes.copyOfRange(1, 33) else bytes
            return ByteArray(32 - unsigned.size) + unsigned
        }
        val r = integer()
        val s = integer()
        if (pos != der.size) throw IllegalStateException("der_trailing")
        return r + s
    }

    private fun sign(call: MethodCall): String {
        val method = call.argument<String>("method") ?: throw IllegalStateException("method")
        val rawTarget = call.argument<String>("htu") ?: throw IllegalStateException("url")
        val accessToken = call.argument<String>("accessToken")
        val expectedOrigin = call.argument<String>("origin")
            ?: throw IllegalStateException("origin")
        if (!Regex("^[A-Z]{3,8}$").matches(method) ||
            rawTarget.length > 2048 || rawTarget.length < 10 ||
            (accessToken != null && (accessToken.length < 32 || accessToken.length > 4096))) {
            throw IllegalStateException("input")
        }
        val url = URI(rawTarget)
        val origin = URI(expectedOrigin)
        if (url.scheme != "https" || url.rawQuery != null || url.rawFragment != null ||
            url.userInfo != null || url.host.isNullOrBlank() || url.host != origin.host ||
            origin.scheme != "https" || origin.path !in setOf("", "/") ||
            origin.rawQuery != null || origin.rawFragment != null ||
            url.port != origin.port || url.scheme != origin.scheme) {
            throw IllegalStateException("target")
        }
        val pair = getOrCreate(expectedOrigin)
        val public = pair.public as ECPublicKey
        val header = JSONObject()
            .put("alg", "ES256").put("typ", "dpop+jwt")
            .put("jwk", JSONObject()
                .put("kty", "EC").put("crv", "P-256")
                .put("x", fixed32(public.w.affineX))
                .put("y", fixed32(public.w.affineY)))
        val payload = JSONObject()
            .put("htm", method).put("htu", rawTarget)
            .put("iat", System.currentTimeMillis() / 1000)
            .put("jti", UUID.randomUUID().toString())
        if (accessToken != null) {
            payload.put("ath", b64(MessageDigest.getInstance("SHA-256")
                .digest(accessToken.toByteArray(StandardCharsets.US_ASCII))))
        }
        val signingInput = b64(header.toString().toByteArray(StandardCharsets.UTF_8)) +
            "." + b64(payload.toString().toByteArray(StandardCharsets.UTF_8))
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(pair.private)
        signer.update(signingInput.toByteArray(StandardCharsets.US_ASCII))
        return signingInput + "." + b64(derToP1363(signer.sign()))
    }
}
