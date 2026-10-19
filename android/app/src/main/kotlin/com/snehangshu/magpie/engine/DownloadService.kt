package com.snehangshu.magpie.engine

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.snehangshu.magpie.storage.MediaStoreSaver
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/** Arguments of `startDownload` (see CLAUDE.md). */
data class DownloadRequest(
    val id: String,
    val url: String,
    val formatId: String,
    val outputType: String,
    val targetDir: String,
    val title: String?,
    /** 1-based item of a `post` to save alone; null saves every item. */
    val item: Int? = null,
)

/**
 * Runs yt-dlp downloads in a `dataSync` foreground service so they survive the
 * app being backgrounded, then copies each file into shared storage.
 * Reports progress through [DownloadEvents] and a notification.
 */
class DownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val slots = Semaphore(MAX_PARALLEL)

    // Touched from the main thread (start, cancel, finish) and IO (progress).
    private val tasks = ConcurrentHashMap<String, DownloadTask>()
    private val jobs = ConcurrentHashMap<String, Job>()
    private var lastStartId = 0

    private lateinit var notifications: DownloadNotifications

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notifications = DownloadNotifications(this)
        // Leftovers from a process that died mid-download.
        workRoot().deleteRecursively()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        when (intent?.action) {
            ACTION_START -> {
                // Required promptly after startForegroundService().
                goForeground()
                intent.toRequest()?.let(::enqueue)
            }
            ACTION_CANCEL -> intent.getStringExtra(EXTRA_ID)?.let(::cancel)
        }
        stopIfIdle()
        return START_NOT_STICKY
    }

    // Android 15+ caps dataSync services at 6 hours a day; stop cleanly when told.
    override fun onTimeout(startId: Int, fgsType: Int) {
        jobs.keys.forEach(::cancel)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        jobs.keys.forEach { YoutubeDL.getInstance().destroyProcessById(it) }
        scope.cancel()
        activeIds.clear()
        super.onDestroy()
    }

    private fun goForeground() {
        ServiceCompat.startForeground(
            this,
            DownloadNotifications.FOREGROUND_ID,
            notifications.progress(tasks.values),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
    }

    private fun enqueue(request: DownloadRequest) {
        if (tasks.containsKey(request.id)) return
        val task = DownloadTask(request)
        tasks[request.id] = task
        activeIds += request.id
        publish(task, force = true)
        jobs[request.id] = scope.launch {
            try {
                slots.withPermit { download(task) }
            } catch (e: CancellationException) {
                task.state = STATE_CANCELLED
                throw e
            } catch (e: Exception) {
                val error = EngineErrors.from(e)
                if (error.code == EngineErrors.CANCELLED) {
                    task.state = STATE_CANCELLED
                } else {
                    task.state = STATE_FAILED
                    task.error = error.code
                }
            } finally {
                withContext(NonCancellable + Dispatchers.Main) { finish(task) }
            }
        }
    }

    private fun cancel(id: String) {
        // Kills a running yt-dlp process; cancelling the job covers a queued one.
        YoutubeDL.getInstance().destroyProcessById(id)
        jobs[id]?.cancel()
    }

    private suspend fun download(task: DownloadTask) {
        val workDir = File(workRoot(), task.id)
        workDir.deleteRecursively()
        workDir.mkdirs()
        try {
            Engine.ensureInitialized(this)
            task.state = STATE_RUNNING
            publish(task, force = true)

            val files = if (task.request.formatId == FORMAT_POST) {
                downloadPost(task, workDir)
            } else {
                listOf(downloadFormat(task, workDir))
            }
            task.state = STATE_MERGING
            task.percent = 100f
            publish(task, force = true)

            val uris = files.map { MediaStoreSaver.save(this, it, task.request.targetDir).toString() }
            task.filePath = uris.first()
            task.filePaths = uris.takeIf { it.size > 1 }
            task.mimeType = MediaStoreSaver.mimeTypeOf(files.first())
            task.state = STATE_SAVED
        } finally {
            workDir.deleteRecursively()
        }
    }

    /** Downloads the `-f` selector of [task]; returns the finished file. */
    private fun downloadFormat(task: DownloadTask, workDir: File): File {
        val request = YoutubeDLRequest(task.request.url).apply {
            addOption("-f", task.request.formatId)
            addOption("-o", File(workDir, "%(title).150B.%(ext)s").absolutePath)
            addOption("--no-playlist")
            addOption("--no-mtime")
        }
        // "137+140" downloads two streams one after the other.
        val streams = task.request.formatId.split('+').size
        var stream = -1
        YoutubeDL.getInstance().execute(request, task.id) { percent, eta, line ->
            when {
                line.startsWith("[download] Destination:") -> stream++
                line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]") ->
                    task.state = STATE_MERGING
            }
            if (task.state == STATE_RUNNING && percent >= 0) {
                val done = stream.coerceIn(0, streams - 1) + percent / 100f
                task.percent = (done / streams * 100f).coerceIn(0f, 100f)
                task.etaSeconds = eta.takeIf { it >= 0 }
                task.speed = SPEED.find(line)?.groupValues?.get(1)
            }
            publish(task)
        }
        return workDir.listFiles()
            ?.filter { it.isFile && it.extension !in TEMP_EXTENSIONS }
            ?.maxByOrNull { it.length() }
            ?: throw YoutubeDLException("yt-dlp finished without producing a file")
    }

    /**
     * Saves every item of a post ([FORMAT_POST]): videos in the best quality,
     * and for items without formats (photos) the image yt-dlp lists as their
     * thumbnail. Returns the files in post order.
     */
    private fun downloadPost(task: DownloadTask, workDir: File): List<File> {
        val request = YoutubeDLRequest(task.request.url).apply {
            addOption("-f", "bv*+ba/b")
            // Photos have no format to download: yt-dlp reports an error for
            // each, after writing its image, and goes on with the next item.
            addOption("--ignore-no-formats-error")
            addOption("--ignore-errors")
            addOption("--write-thumbnail")
            task.request.item?.let { addOption("-I", it.toString()) }
            // "<index> <id>.<ext>"; ids have no spaces.
            addOption("-o", File(workDir, "%(playlist_index|0)s %(id)s.%(ext)s").absolutePath)
            addOption("--no-mtime")
        }
        var item = 0
        var items = 1
        val run: () -> Unit = {
            YoutubeDL.getInstance().execute(request, task.id) { percent, eta, line ->
                ITEM.find(line)?.let { match ->
                    item = match.groupValues[1].toInt() - 1
                    items = match.groupValues[2].toInt()
                }
                if (line.startsWith("[Merger]")) task.state = STATE_MERGING
                if (line.startsWith("[download] Destination:")) task.state = STATE_RUNNING
                val done = item + (percent.takeIf { it >= 0 } ?: 0f) / 100f
                task.percent = (done / items * 100f).coerceIn(0f, 100f)
                task.etaSeconds = eta.takeIf { it >= 0 && items == 1 }
                task.speed = SPEED.find(line)?.groupValues?.get(1)
                publish(task)
            }
        }
        try {
            run()
        } catch (e: YoutubeDLException) {
            // Only photos' "No video formats found!" is expected; anything
            // else (network, a video that failed) fails the whole post.
            val unexpected = e.message.orEmpty().lines()
                .filter { it.startsWith("ERROR:") }
                .any { !it.contains(NO_FORMATS) }
            if (unexpected) throw e
        }

        val files = workDir.listFiles()
            ?.filter { it.isFile && it.extension !in TEMP_EXTENSIONS }
            .orEmpty()
        val saved = files.groupBy { it.name.substringBefore('.') }
            .toSortedMap(compareBy { it.substringBefore(' ').toIntOrNull() ?: 0 })
            // A video's thumbnail is written too; keep only the video.
            .map { (_, group) ->
                group.firstOrNull { MediaStoreSaver.mimeTypeOf(it).startsWith("video/") }
                    ?: group.maxBy { it.length() }
            }
        if (saved.isEmpty()) throw YoutubeDLException("yt-dlp finished without producing a file")

        val title = task.request.title?.let(::safeFileName)?.takeIf { it.isNotBlank() }
        return saved.mapIndexed { i, file ->
            // Instagram's photos are JPEGs whose URL ends in ".heic".
            val ext = MediaStoreSaver.imageExtensionOf(file) ?: file.extension
            val base = title ?: file.name.substringBefore('.').substringAfter(' ')
            // One item keeps its place in the post, so items saved one by one
            // don't all share the post's name.
            val number = task.request.item ?: (i + 1).takeIf { saved.size > 1 }
            val name = if (number != null) "$base $number.$ext" else "$base.$ext"
            File(workDir, name).also { file.renameTo(it) }
        }
    }

    /** Runs on the main thread once [task] has saved, failed or been cancelled. */
    private fun finish(task: DownloadTask) {
        tasks.remove(task.id)
        jobs.remove(task.id)
        activeIds -= task.id
        // Kept until Dart collects it, in case nobody is listening right now.
        DownloadResults.put(this, task.toEvent())
        publish(task, force = true)
        notifications.result(task)
        if (tasks.isNotEmpty()) notifications.updateProgress(tasks.values, force = true)
        stopIfIdle()
    }

    private fun stopIfIdle() {
        if (jobs.isNotEmpty()) return
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        // Keeps the service if a newer start command is already queued.
        stopSelfResult(lastStartId)
    }

    /** Sends [task] to Dart and the notification, at most a few times a second. */
    private fun publish(task: DownloadTask, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (force || task.state != task.publishedState || now - task.publishedAt >= EVENT_INTERVAL_MS) {
            task.publishedAt = now
            task.publishedState = task.state
            DownloadEvents.emit(task.toEvent())
        }
        if (task.state in ACTIVE_STATES) notifications.updateProgress(tasks.values, force)
    }

    private fun workRoot() = File(noBackupFilesDir, "downloads")

    private fun Intent.toRequest(): DownloadRequest? = DownloadRequest(
        id = getStringExtra(EXTRA_ID) ?: return null,
        url = getStringExtra(EXTRA_URL) ?: return null,
        formatId = getStringExtra(EXTRA_FORMAT_ID) ?: return null,
        outputType = getStringExtra(EXTRA_OUTPUT_TYPE) ?: return null,
        targetDir = getStringExtra(EXTRA_TARGET_DIR) ?: return null,
        title = getStringExtra(EXTRA_TITLE),
        item = getIntExtra(EXTRA_ITEM, 0).takeIf { it > 0 },
    )

    companion object {
        const val STATE_QUEUED = "queued"
        const val STATE_RUNNING = "running"
        const val STATE_MERGING = "merging"
        const val STATE_SAVED = "saved"
        const val STATE_FAILED = "failed"
        const val STATE_CANCELLED = "cancelled"
        private val ACTIVE_STATES = setOf(STATE_QUEUED, STATE_RUNNING, STATE_MERGING)

        internal const val ACTION_START = "com.snehangshu.magpie.download.START"
        internal const val ACTION_CANCEL = "com.snehangshu.magpie.download.CANCEL"
        internal const val EXTRA_ID = "id"
        private const val EXTRA_URL = "url"
        private const val EXTRA_FORMAT_ID = "formatId"
        private const val EXTRA_OUTPUT_TYPE = "outputType"
        private const val EXTRA_TARGET_DIR = "targetDir"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ITEM = "item"

        private const val MAX_PARALLEL = 2
        private const val EVENT_INTERVAL_MS = 250L
        private val TEMP_EXTENSIONS = setOf("part", "ytdl", "temp")

        /** `startDownload` selector for every item of the link (see CLAUDE.md). */
        private const val FORMAT_POST = "post"
        private const val NO_FORMATS = "No video formats found"

        // "[download] Downloading item 3 of 19"
        private val ITEM = Regex("""Downloading item (\d+) of (\d+)""")

        private fun safeFileName(name: String) =
            name.replace(Regex("""[\\/:*?"<>|\p{Cntrl}]"""), "_").trim().take(120)

        // "[download]  45.3% of ~ 10.00MiB at    2.31MiB/s ETA 00:03"
        private val SPEED = Regex("""\bat\s+(\S+/s)""")

        /** Ids queued or running in this process. */
        private val activeIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Must be called while the app is in the foreground. */
        fun start(context: Context, request: DownloadRequest) {
            val intent = Intent(context, DownloadService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_ID, request.id)
                .putExtra(EXTRA_URL, request.url)
                .putExtra(EXTRA_FORMAT_ID, request.formatId)
                .putExtra(EXTRA_OUTPUT_TYPE, request.outputType)
                .putExtra(EXTRA_TARGET_DIR, request.targetDir)
                .putExtra(EXTRA_TITLE, request.title)
                .putExtra(EXTRA_ITEM, request.item ?: 0)
            ContextCompat.startForegroundService(context, intent)
        }

        /** Returns false when [id] is not queued or running. */
        fun cancel(context: Context, id: String): Boolean {
            if (id !in activeIds) return false
            context.startService(
                Intent(context, DownloadService::class.java)
                    .setAction(ACTION_CANCEL)
                    .putExtra(EXTRA_ID, id),
            )
            return true
        }
    }
}

/** Mutable state of one download; written from the download's IO thread. */
internal class DownloadTask(val request: DownloadRequest) {
    val id get() = request.id

    @Volatile var state = DownloadService.STATE_QUEUED
    @Volatile var percent = 0f
    @Volatile var etaSeconds: Long? = null
    @Volatile var speed: String? = null
    @Volatile var filePath: String? = null
    @Volatile var filePaths: List<String>? = null
    @Volatile var mimeType: String? = null
    @Volatile var error: String? = null

    var publishedAt = 0L
    var publishedState: String? = null

    fun toEvent(): Map<String, Any?> = mapOf(
        "id" to id,
        "percent" to percent.toDouble(),
        "etaSeconds" to etaSeconds?.toInt(),
        "speed" to speed,
        "state" to state,
        "filePath" to filePath,
        "filePaths" to filePaths,
        "error" to error,
    )
}
