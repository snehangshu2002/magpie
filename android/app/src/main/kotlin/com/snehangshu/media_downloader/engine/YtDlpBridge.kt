package com.snehangshu.media_downloader.engine

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.mapper.VideoFormat
import com.yausername.youtubedl_android.mapper.VideoInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Native side of the `app/engine` channel contract (see CLAUDE.md).
 * It only executes requests; Dart decides what to run.
 */
class YtDlpBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val initMutex = Mutex()
    private var initialized = false

    private var methodChannel: MethodChannel? = null
    private var progressChannel: EventChannel? = null

    // Receives `app/engine/progress` events once DownloadService is in place.
    private var progressSink: EventChannel.EventSink? = null

    fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        progressChannel = EventChannel(messenger, PROGRESS_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    fun detach() {
        methodChannel?.setMethodCallHandler(null)
        progressChannel?.setStreamHandler(null)
        methodChannel = null
        progressChannel = null
        progressSink = null
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> respond(result) {
                ensureInitialized()
                mapOf("ytDlpVersion" to YoutubeDL.getInstance().version(context))
            }

            "fetchInfo" -> respond(result) {
                ensureInitialized()
                YoutubeDL.getInstance().getInfo(call.requireString("url")).toPayload()
            }

            "cancelDownload" -> result.success(
                YoutubeDL.getInstance().destroyProcessById(call.requireString("id")),
            )

            "updateEngine" -> respond(result) {
                ensureInitialized()
                val channel = when (call.argument<String>("channel")) {
                    "nightly" -> YoutubeDL.UpdateChannel.NIGHTLY
                    else -> YoutubeDL.UpdateChannel.STABLE
                }
                val status = YoutubeDL.getInstance().updateYoutubeDL(context, channel)
                mapOf(
                    "status" to when (status) {
                        YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "alreadyUpToDate"
                        else -> "done"
                    },
                    "version" to YoutubeDL.getInstance().version(context),
                )
            }

            // startDownload arrives together with DownloadService (v1 scope item 3).
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        progressSink = events
    }

    override fun onCancel(arguments: Any?) {
        progressSink = null
    }

    /** Unpacks Python, yt-dlp and FFmpeg on first use; later calls return at once. */
    private suspend fun ensureInitialized() = initMutex.withLock {
        if (!initialized) {
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            initialized = true
        }
    }

    /** Runs [block] on the IO dispatcher and replies with its value or a typed error. */
    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(withContext(Dispatchers.IO) { block() })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = EngineErrors.from(e)
                result.error(error.code, error.message, null)
            }
        }
    }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    private fun VideoInfo.toPayload(): Map<String, Any?> = mapOf(
        "title" to (title ?: fulltitle ?: id),
        "thumbnail" to thumbnail,
        "duration" to duration.takeIf { it > 0 },
        "extractor" to extractor,
        "formats" to formats.orEmpty().map { it.toPayload() },
    )

    private fun VideoFormat.toPayload(): Map<String, Any?> = mapOf(
        "formatId" to formatId,
        "ext" to ext,
        "width" to width.takeIf { it > 0 },
        "height" to height.takeIf { it > 0 },
        "fps" to fps.takeIf { it > 0 },
        "vcodec" to vcodec,
        "acodec" to acodec,
        "fileSize" to (fileSize.takeIf { it > 0 } ?: fileSizeApproximate.takeIf { it > 0 }),
        "note" to formatNote,
    )

    private companion object {
        const val METHOD_CHANNEL = "app/engine"
        const val PROGRESS_CHANNEL = "app/engine/progress"
    }
}
