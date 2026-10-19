package com.snehangshu.magpie.engine

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.storage.StorageException
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
import kotlinx.coroutines.withContext

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
                YoutubeDL.getInstance().getInfo(call.requireString("url")).toPayload()
            }

            "startDownload" -> respond(result) {
                val request = DownloadRequest(
                    id = call.requireString("id"),
                    url = call.requireString("url"),
                    formatId = call.requireString("formatId"),
                    outputType = call.requireString("outputType"),
                    targetDir = call.requireString("targetDir"),
                    title = call.argument<String>("title"),
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
                Engine.ensureInitialized(context)
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
