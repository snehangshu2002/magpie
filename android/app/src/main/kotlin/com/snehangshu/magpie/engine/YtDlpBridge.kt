package com.snehangshu.magpie.engine

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.storage.StorageException
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
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
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native side of the `app/engine` channel contract (see CLAUDE.md).
 * It only executes requests; Dart decides what to run.
 */
class YtDlpBridge(
    private val context: Context,
    private val host: ActivityHost,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var methodChannel: MethodChannel? = null
    private var progressChannel: EventChannel? = null

    // Receives `app/engine/progress` events while Dart listens.
    private var progressSink: EventChannel.EventSink? = null

    fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        progressChannel = EventChannel(messenger, PROGRESS_CHANNEL).also {
            it.setStreamHandler(this)
        }
        scope.launch {
            DownloadEvents.events.collect { progressSink?.success(it) }
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
                Engine.ensureInitialized(context)
                mapOf("ytDlpVersion" to YoutubeDL.getInstance().version(context))
            }

            "fetchInfo" -> respond(result) {
                Engine.ensureInitialized(context)
                fetchInfo(call.requireString("url"))
            }

            "startDownload" -> respond(result) {
                val request = DownloadRequest(
                    id = call.requireString("id"),
                    url = call.requireString("url"),
                    formatId = call.requireString("formatId"),
                    outputType = call.requireString("outputType"),
                    targetDir = call.requireString("targetDir"),
                    title = call.argument<String>("title"),
                    item = call.argument<Int>("item"),
                )
                requestDownloadPermissions()
                withContext(Dispatchers.Main) { DownloadService.start(context, request) }
                mapOf("id" to request.id)
            }

            "cancelDownload" -> respond(result) {
                withContext(Dispatchers.Main) {
                    DownloadService.cancel(context, call.requireString("id"))
                }
            }

            "takeFinishedDownloads" -> respond(result) { DownloadResults.take(context) }

            "updateEngine" -> respond(result) {
                val channel = when (call.argument<String>("channel")) {
                    "nightly" -> YoutubeDL.UpdateChannel.NIGHTLY
                    else -> YoutubeDL.UpdateChannel.STABLE
                }
                val status = Engine.update(context, channel)
                mapOf(
                    "status" to when (status) {
                        YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "alreadyUpToDate"
                        else -> "done"
                    },
                    "version" to YoutubeDL.getInstance().version(context),
                )
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        progressSink = events
    }

    override fun onCancel(arguments: Any?) {
        progressSink = null
    }

    /**
     * Asks for the progress notification (Android 13+; downloads run without
     * it) and, before Android 10, for write access to shared storage, which
     * saving cannot do without.
     */
    private suspend fun requestDownloadPermissions() {
        val wanted = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
        }
        if (wanted.isEmpty()) return
        host.requestPermissions(wanted)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw StorageException("Storage permission denied")
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
                // yt-dlp's own message only reaches Dart as a code; keep it in logcat.
                Log.w(TAG, "${error.code}: ${e.message}", e)
                result.error(error.code, error.message, null)
            }
        }
    }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    /**
     * yt-dlp's JSON for [url]. `-J` keeps a post with several items (an
     * Instagram carousel) as one result with `entries`; items without formats
     * (photos) are reported instead of failing the whole link.
     */
    private fun fetchInfo(url: String): Map<String, Any?> {
        val request = YoutubeDLRequest(url).apply {
            addOption("-J")
            addOption("--no-playlist")
            addOption("--ignore-no-formats-error")
            addOption("--no-warnings")
        }
        val json = JSONObject(YoutubeDL.getInstance().execute(request).out)
        val entries = json.optJSONArray("entries")?.objects()
        return mapOf(
            "title" to (json.string("title") ?: json.string("fulltitle") ?: json.string("id")),
            "thumbnail" to (json.string("thumbnail") ?: entries?.firstNotNullOfOrNull { it.string("thumbnail") }),
            "duration" to json.positiveInt("duration"),
            "extractor" to (json.string("extractor") ?: entries?.firstNotNullOfOrNull { it.string("extractor") }),
            "formats" to json.formatsPayload(),
            "entries" to entries?.map {
                mapOf(
                    "thumbnail" to it.string("thumbnail"),
                    "duration" to it.positiveInt("duration"),
                    "formats" to it.formatsPayload(),
                )
            },
        )
    }

    private fun JSONObject.formatsPayload(): List<Map<String, Any?>> =
        optJSONArray("formats")?.objects().orEmpty().map {
            mapOf(
                "formatId" to it.string("format_id"),
                "ext" to it.string("ext"),
                "width" to it.positiveInt("width"),
                "height" to it.positiveInt("height"),
                "fps" to it.positiveInt("fps"),
                "vcodec" to it.string("vcodec"),
                "acodec" to it.string("acodec"),
                "fileSize" to (it.positiveLong("filesize") ?: it.positiveLong("filesize_approx")),
                "note" to it.string("format_note"),
            )
        }

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).mapNotNull { optJSONObject(it) }

    // JSON null and missing keys both become null (optString would give "null").
    private fun JSONObject.string(key: String): String? =
        if (isNull(key)) null else opt(key)?.toString()

    // yt-dlp writes some counts as floats (fps 29.97, duration 12.5).
    private fun JSONObject.positiveInt(key: String): Int? =
        (opt(key) as? Number)?.toInt()?.takeIf { it > 0 }

    private fun JSONObject.positiveLong(key: String): Long? =
        (opt(key) as? Number)?.toLong()?.takeIf { it > 0 }

    private companion object {
        const val METHOD_CHANNEL = "app/engine"
        const val PROGRESS_CHANNEL = "app/engine/progress"
        const val TAG = "YtDlpBridge"
    }
}
