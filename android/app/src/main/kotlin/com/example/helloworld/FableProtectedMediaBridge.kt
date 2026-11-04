package com.example.helloworld

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.min

/**
 * RC120 first Android Media3 progressive adapter. All actual bytes come only
 * through Dart's verified session broker. The synthetic fable-media scheme is
 * intercepted by DataSource and is NEVER opened by a network client.
 *
 * This still requires real device, codec, R2 and backend testing (P6).
 */
@UnstableApi
internal class FableProtectedMediaBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "fable/protected_player_v1")
    private val main = Handler(Looper.getMainLooper())
    private val surfaces = mutableMapOf<Int, FableProtectedMediaSurface>()
    private val requestSequence = AtomicLong(0)

    fun register(registry: PlatformViewRegistry, context: Context) {
        registry.registerViewFactory(
            "fable/protected_media_surface",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val surface = FableProtectedMediaSurface(context, viewId, this@FableProtectedMediaBridge)
                    surfaces[viewId] = surface
                    return surface
                }
            }
        )
        channel.setMethodCallHandler { call, result ->
            try {
                val args = call.arguments as? Map<*, *>
                    ?: throw IllegalArgumentException("Native player arguments required")
                val viewId = (args["viewId"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Missing platform view")
                val surface = surfaces[viewId]
                    ?: throw IllegalStateException("Unknown native player view")
                when (call.method) {
                    "prepare" -> {
                        val total = (args["totalLength"] as? Number)?.toLong() ?: -1L
                        val mime = args["mimeType"] as? String ?: ""
                        val epoch = (args["rangeEpoch"] as? Number)?.toInt() ?: -1
                        surface.prepare(total, mime, epoch)
                        result.success(null)
                    }
                    "play" -> { surface.play(); result.success(null) }
                    "pause" -> { surface.pause(); result.success(null) }
                    "seek" -> {
                        val millis = (args["millis"] as? Number)?.toLong() ?: -1L
                        val epoch = (args["rangeEpoch"] as? Number)?.toInt() ?: -1
                        surface.seek(millis, epoch)
                        result.success(null)
                    }
                    "stop" -> { surface.stop(); result.success(null) }
                    "dispose" -> { surface.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Throwable) {
                // Do not relay native exceptions containing raw media headers.
                result.error("protected_player_rejected", "Native player command rejected", null)
            }
        }
    }

    fun unregister(viewId: Int) {
        surfaces.remove(viewId)
    }

    fun stopAll() {
        surfaces.values.toList().forEach { it.stop() }
    }

    fun disposeAll() {
        stopAll()
        surfaces.clear()
        channel.setMethodCallHandler(null)
    }

    /** Called from Media3's loader thread; Dart callbacks run on the main thread. */
    @Throws(IOException::class)
    fun read(
        surface: FableProtectedMediaSurface, generation: Long,
        offset: Long, length: Int, epoch: Int, abandoned: () -> Boolean
    ): ByteArray {
        if (length <= 0 || length > 524288 || offset < 0) {
            throw IOException("Invalid bounded native media request")
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw IOException("Never block Flutter main thread for media bytes")
        }
        val latch = CountDownLatch(1)
        val output = AtomicReference<ByteArray?>(null)
        val id = requestSequence.incrementAndGet()
        main.post {
            if (abandoned() || !surface.valid(generation, epoch)) {
                latch.countDown()
                return@post
            }
            channel.invokeMethod("readRange", mapOf(
                "viewId" to surface.viewId,
                "requestId" to id,
                "start" to offset,
                "length" to length,
                "rangeEpoch" to epoch
            ), object : MethodChannel.Result {
                override fun success(answer: Any?) {
                    try {
                        val record = answer as? Map<*, *> ?: return
                        if (record["status"] != "bytes") return
                        val bytes = record["bytes"] as? ByteArray ?: return
                        val start = (record["start"] as? Number)?.toLong()
                        val total = (record["totalLength"] as? Number)?.toLong()
                        val mime = record["mimeType"] as? String
                        if (start != offset || total != surface.totalLength ||
                            mime != surface.mimeType || bytes.isEmpty() ||
                            bytes.size > length || bytes.size > 524288) return
                        if (!abandoned() && surface.valid(generation, epoch)) {
                            output.set(bytes)
                        }
                    } finally {
                        latch.countDown()
                    }
                }
                override fun error(code: String, message: String?, details: Any?) {
                    latch.countDown()
                }
                override fun notImplemented() { latch.countDown() }
            })
        }
        if (!latch.await(15, TimeUnit.SECONDS) || abandoned() ||
            !surface.valid(generation, epoch)) {
            throw IOException("Protected media range cancelled or timed out")
        }
        return output.get() ?: throw IOException("Protected media range refused")
    }
}

@UnstableApi
internal class FableProtectedMediaSurface(
    context: Context, val viewId: Int,
    private val bridge: FableProtectedMediaBridge
) : PlatformView {
    private val playerView = PlayerView(context).apply {
        useController = false
        setKeepContentOnPlayerReset(false)
        setBackgroundColor(android.graphics.Color.BLACK)
    }
    private var player: ExoPlayer? = null
    @Volatile private var generation: Long = 0L
    @Volatile var rangeEpoch: Int = 0
        private set
    @Volatile var totalLength: Long = 0L
        private set
    @Volatile var mimeType: String = ""
        private set
    @Volatile private var active = false

    override fun getView(): View = playerView

    fun valid(requestGeneration: Long, epoch: Int): Boolean =
        active && requestGeneration == generation && epoch == rangeEpoch

    fun prepare(total: Long, mime: String, epoch: Int) {
        if (total <= 0 || epoch < 0 ||
            !Regex("^(audio|video)/[a-z0-9][a-z0-9.+_-]*$").matches(mime)) {
            throw IllegalArgumentException("Unsupported protected player metadata")
        }
        stop()
        totalLength = total
        mimeType = mime
        rangeEpoch = epoch
        active = true
        val factory = DataSource.Factory {
            FableProtectedRangeDataSource(this, bridge, generation, rangeEpoch)
        }
        val mediaSource = ProgressiveMediaSource.Factory(factory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(0))
            .createMediaSource(
                MediaItem.Builder()
                    .setUri(Uri.parse("fable-media://session/content"))
                    .setMimeType(mime)
                    .build()
            )
        val created = ExoPlayer.Builder(playerView.context).build()
        player = created
        playerView.player = created
        created.setMediaSource(mediaSource)
        created.prepare()
    }

    fun play() {
        if (!active) throw IllegalStateException("Stopped")
        player?.play() ?: throw IllegalStateException("Not prepared")
    }

    fun pause() {
        if (!active) throw IllegalStateException("Stopped")
        player?.pause() ?: throw IllegalStateException("Not prepared")
    }

    fun seek(millis: Long, epoch: Int) {
        if (!active || millis < 0 || epoch <= rangeEpoch) {
            throw IllegalArgumentException("Invalid session seek")
        }
        rangeEpoch = epoch
        player?.seekTo(millis) ?: throw IllegalStateException("Not prepared")
    }

    fun stop() {
        // Revoke before releasing decoders, so background loader replies are
        // never allowed into a new account's player surface.
        active = false
        generation++
        player?.stop()
        player?.clearMediaItems()
        playerView.player = null
        player?.release()
        player = null
        totalLength = 0L
        mimeType = ""
    }

    override fun dispose() {
        stop()
        bridge.unregister(viewId)
    }
}

@UnstableApi
private class FableProtectedRangeDataSource(
    private val owner: FableProtectedMediaSurface,
    private val bridge: FableProtectedMediaBridge,
    private val generation: Long,
    private val epoch: Int
) : DataSource {
    @Volatile private var closed = false
    private var uri: Uri? = null
    private var offset = 0L
    private var remaining = 0L
    private var cache = ByteArray(0)
    private var cachePosition = 0

    override fun addTransferListener(transferListener: TransferListener) {
        // No networking: native bytes are supplied by the guarded Dart port.
    }

    override fun open(dataSpec: DataSpec): Long {
        if (closed || !owner.valid(generation, epoch) ||
            dataSpec.uri.scheme != "fable-media" || dataSpec.position < 0 ||
            dataSpec.position > owner.totalLength) {
            throw IOException("Protected DataSource denied")
        }
        uri = dataSpec.uri
        offset = dataSpec.position
        remaining = owner.totalLength - offset
        if (dataSpec.length != C.LENGTH_UNSET.toLong()) {
            if (dataSpec.length < 0) throw IOException("Invalid range")
            remaining = min(remaining, dataSpec.length)
        }
        return remaining
    }

    override fun read(buffer: ByteArray, bufferOffset: Int, readLength: Int): Int {
        if (readLength == 0) return 0
        if (closed || !owner.valid(generation, epoch) ||
            bufferOffset < 0 || readLength < 0 ||
            bufferOffset > buffer.size - readLength) {
            throw IOException("Protected DataSource invalidated")
        }
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        if (cachePosition == cache.size) {
            val count = min(65536L, remaining).toInt()
            cache = bridge.read(owner, generation, offset, count, epoch) {
                closed || !owner.valid(generation, epoch)
            }
            cachePosition = 0
        }
        val copied = min(readLength, cache.size - cachePosition)
        if (copied <= 0) throw IOException("No protected media bytes")
        System.arraycopy(cache, cachePosition, buffer, bufferOffset, copied)
        // Identity may be revoked on the UI thread *during* this copy.
        // Fail closed before handing any stale bytes back to Media3.
        if (closed || !owner.valid(generation, epoch)) {
            java.util.Arrays.fill(buffer, bufferOffset, bufferOffset + copied, 0.toByte())
            throw IOException("Protected media invalidated during copy")
        }
        cachePosition += copied
        offset += copied
        remaining -= copied
        return copied
    }

    override fun getUri(): Uri? = uri
    override fun getResponseHeaders(): Map<String, List<String>> = emptyMap()

    override fun close() {
        closed = true
        cache.fill(0)
        cache = ByteArray(0)
        cachePosition = 0
        uri = null
    }
}
