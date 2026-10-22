package com.snehangshu.magpie.engine

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.snehangshu.magpie.storage.MediaStoreSaver
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.io.FileNotFoundException
import java.util.Locale
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
    val targetDir: String,
    val title: String?,
    /**
     * 1-based items of a `post` to save, in order; null saves every item.
     * For `images`, the place in the post of each of [imageUrls].
     */
    val items: List<Int>? = null,
    /** Full-size photos an `images` job downloads, in order. */
    val imageUrls: List<String>? = null,
    /** Extra yt-dlp arguments Dart chose from Settings (see CLAUDE.md). */
    val options: List<String> = emptyList(),
    /** Saves the items of a playlist ([items]: their places) instead of one video. */
    val playlist: Boolean = false,
    /** Skips videos saved before (`--download-archive`). */
    val archive: Boolean = false,
    /** yt-dlp output template for the file name, without the extension. */
    val fileName: String? = null,
    /**
     * Set for a `fitVideo` job: [url] is then the content URI of a saved
     * video to re-encode, not a link.
     */
    val fit: FitSpec? = null,
)

/** The video, or every item of a playlist, was already in the download archive. */
class NothingNewException : Exception("Everything was downloaded before")

/**
 * Runs yt-dlp downloads, and FFmpeg re-encodes of saved videos (`fitVideo`),
 * in a foreground service so they survive the app being backgrounded, then
 * copies each file into shared storage.
 * Reports progress through [DownloadEvents] and a notification.
 */
class DownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val slots = Semaphore(MAX_PARALLEL)

    // Touched from the main thread (start, cancel, finish) and IO (progress).
    private val tasks = ConcurrentHashMap<String, DownloadTask>()
    private val jobs = ConcurrentHashMap<String, Job>()

    // FFmpeg processes of running `fitVideo` jobs, killed on cancel.
    private val processes = ConcurrentHashMap<String, Process>()
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
        processes.values.forEach(Process::destroy)
        scope.cancel()
        activeIds.clear()
        super.onDestroy()
    }

    private fun goForeground() {
        ServiceCompat.startForeground(
            this,
            DownloadNotifications.FOREGROUND_ID,
            notifications.progress(tasks.values),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                // Re-encoding videos is media processing, not a data transfer.
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
                if (error.code == EngineErrors.CANCELLED || task.cancelRequested) {
                    task.state = STATE_CANCELLED
                } else {
                    task.state = STATE_FAILED
                    task.error = error.code
                    // Dart only gets the code; keep yt-dlp's own words in logcat.
                    Log.w(TAG, "${error.code}: ${e.message}", e)
                }
            } finally {
                withContext(NonCancellable + Dispatchers.Main) { finish(task) }
            }
        }
    }

    private fun cancel(id: String) {
        // Kills a running yt-dlp or FFmpeg process; cancelling the job covers a queued one.
        tasks[id]?.cancelRequested = true
        YoutubeDL.getInstance().destroyProcessById(id)
        processes[id]?.destroy()
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

            val fit = task.request.fit
            val files = when {
                fit != null -> listOf(fitVideo(task, fit, workDir))
                task.request.formatId == FORMAT_POST -> downloadPost(task, workDir)
                task.request.formatId == FORMAT_IMAGES -> downloadImages(task, workDir)
                task.request.playlist -> downloadPlaylist(task, workDir)
                else -> listOf(downloadFormat(task, workDir))
            }
            task.state = STATE_MERGING
            task.percent = 100f
            publish(task, force = true)

            val uris = files.map { MediaStoreSaver.save(this, it, task.request.targetDir).toString() }
            keepArchive(task)
            task.filePath = uris.first()
            task.filePaths = uris.takeIf { it.size > 1 }
            task.mimeType = MediaStoreSaver.mimeTypeOf(files.first())
            task.state = STATE_SAVED
        } finally {
            workDir.deleteRecursively()
            archiveCopy(task).delete()
            cookiesCopy(task).delete()
        }
    }

    /** Downloads the `-f` selector of [task]; returns the finished file. */
    private fun downloadFormat(task: DownloadTask, workDir: File): File {
        val request = YoutubeDLRequest(task.request.url).apply {
            addOption("-f", task.request.formatId)
            addOption("-o", File(workDir, "${nameTemplate(task)}.%(ext)s").absolutePath)
            addOption("--no-playlist")
            addOption("--no-mtime")
            addArchive(task)
            applyUserOptions(task)
        }
        // "137+140" downloads two streams one after the other.
        val streams = task.request.formatId.split('+').size
        var stream = -1
        YoutubeDL.getInstance().execute(request, task.id) { percent, eta, line ->
            when {
                line.startsWith("[download] Destination:") -> stream++
                line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]") ||
                    line.startsWith("[EmbedSubtitle]") || line.startsWith("[SponsorBlock]") ->
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
        return finishedFiles(workDir)
            .maxByOrNull { it.length() }
            ?: if (task.request.archive) {
                // yt-dlp skips a video in the archive without an error.
                throw NothingNewException()
            } else {
                throw YoutubeDLException("yt-dlp finished without producing a file")
            }
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
            task.request.items?.let { addOption("-I", it.joinToString(",")) }
            // "<index> <id>.<ext>"; ids have no spaces.
            addOption("-o", File(workDir, "%(playlist_index|0)s %(id)s.%(ext)s").absolutePath)
            addOption("--no-mtime")
            applyUserOptions(task)
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

        val title = task.request.title?.let(::safeFileName)?.takeIf { it.isNotBlank() }
        val saved = postFiles(workDir, title, task.request.items) {
            MediaStoreSaver.mimeTypeOf(it).startsWith("video/")
        }
        if (saved.isEmpty()) throw YoutubeDLException("yt-dlp finished without producing a file")
        return saved
    }

    /**
     * Saves the playlist at [DownloadRequest.url] with the `-f` selector of
     * [task], only the [DownloadRequest.items] when given. An item that fails
     * (private, removed) is skipped; the rest are kept. Returns the files in
     * playlist order, named by their own titles.
     */
    private fun downloadPlaylist(task: DownloadTask, workDir: File): List<File> {
        val request = YoutubeDLRequest(task.request.url).apply {
            addOption("-f", task.request.formatId)
            addOption("--yes-playlist")
            addOption("--ignore-errors")
            task.request.items?.let { addOption("-I", it.joinToString(",")) }
            addArchive(task)
            // "<index> <name>.<ext>"; the index is dropped once saved.
            addOption("-o", File(workDir, "%(playlist_index|0)s ${nameTemplate(task)}.%(ext)s").absolutePath)
            addOption("--no-mtime")
            applyUserOptions(task)
        }
        var item = 0
        var items = 1
        try {
            YoutubeDL.getInstance().execute(request, task.id) { percent, eta, line ->
                ITEM.find(line)?.let { match ->
                    item = match.groupValues[1].toInt() - 1
                    items = match.groupValues[2].toInt()
                }
                if (line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]")) {
                    task.state = STATE_MERGING
                }
                if (line.startsWith("[download] Destination:")) task.state = STATE_RUNNING
                val done = item + (percent.takeIf { it >= 0 } ?: 0f) / 100f
                task.percent = (done / items * 100f).coerceIn(0f, 100f)
                task.etaSeconds = null
                task.speed = SPEED.find(line)?.groupValues?.get(1)
                publish(task)
            }
        } catch (e: YoutubeDLException) {
            // With --ignore-errors yt-dlp still exits with an error when an
            // item failed; keep what it saved. A cancel throws another type.
            if (finishedFiles(workDir).isEmpty()) throw e
        }

        val files = playlistFiles(workDir)
        if (files.isEmpty()) {
            if (task.request.archive) throw NothingNewException()
            throw YoutubeDLException("yt-dlp finished without producing a file")
        }
        return files
    }

    /** The output template for [task]'s file names, without the extension. */
    private fun nameTemplate(task: DownloadTask) =
        task.request.fileName?.takeIf { it.isNotBlank() && '/' !in it } ?: "%(title).150B"

    /**
     * Skips videos saved before, when asked. yt-dlp records a video as soon
     * as it has the file, before it is saved, so it gets a copy of the
     * archive; [keepArchive] adds the new lines once the files are saved.
     */
    private fun YoutubeDLRequest.addArchive(task: DownloadTask) {
        if (!task.request.archive) return
        val copy = archiveCopy(task)
        synchronized(ARCHIVE_LOCK) {
            if (archiveFile().exists()) archiveFile().copyTo(copy, overwrite = true) else copy.delete()
        }
        addOption("--download-archive", copy.absolutePath)
    }

    /** Adds the videos [task] saved to the shared archive. */
    private fun keepArchive(task: DownloadTask) {
        val copy = archiveCopy(task)
        if (!task.request.archive || !copy.exists()) return
        synchronized(ARCHIVE_LOCK) {
            val archive = archiveFile()
            val known = if (archive.exists()) archive.readLines().toSet() else emptySet()
            val added = copy.readLines().filter { it.isNotBlank() && it !in known }
            if (added.isNotEmpty()) archive.appendText(added.joinToString("\n", postfix = "\n"))
        }
    }

    private fun archiveFile() = File(noBackupFilesDir, "archive.txt")

    // Next to the job's work dir, not in it: that dir is read for the downloaded files.
    private fun archiveCopy(task: DownloadTask) = File(workRoot(), "${task.id}.archive.txt")

    private fun cookiesCopy(task: DownloadTask) = File(workRoot(), "${task.id}.cookies.txt")

    /** Settings-driven arguments from Dart, and the user's sign-ins. */
    private fun YoutubeDLRequest.applyUserOptions(task: DownloadTask) {
        if (task.request.options.isNotEmpty()) addCommands(task.request.options)
        Cookies.apply(this@DownloadService, this, cookiesCopy(task))
    }

    /**
     * Saves the photos at [DownloadRequest.imageUrls] ([FORMAT_IMAGES]) as
     * the site serves them, named like a post's items. Returns the files in
     * order.
     */
    private fun downloadImages(task: DownloadTask, workDir: File): List<File> {
        val urls = task.request.imageUrls.orEmpty()
        require(urls.isNotEmpty()) { "No image URLs" }
        val title = task.request.title?.let(::safeFileName)?.takeIf { it.isNotBlank() } ?: "image"
        val places = task.request.items?.takeIf { it.size == urls.size }
        val started = SystemClock.elapsedRealtime()
        var done = 0L
        return urls.mapIndexed { i, url ->
            val file = File(workDir, "$i.download")
            ImageFetcher.fetch(url, file, task.request.options, isCancelled = { task.cancelRequested }) { read, total ->
                val part = if (total != null) read.toFloat() / total else 0f
                task.percent = ((i + part.coerceIn(0f, 1f)) / urls.size * 100f).coerceIn(0f, 100f)
                val seconds = (SystemClock.elapsedRealtime() - started) / 1000f
                if (seconds > 0.5f) task.speed = formatSpeed((done + read) / seconds)
                publish(task)
            }
            done += file.length()
            val ext = MediaStoreSaver.imageExtensionOf(file)
                ?: url.substringBefore('?').substringAfterLast('/').substringAfterLast('.', "")
                    .lowercase().takeIf { it in IMAGE_EXTENSIONS }
                ?: "jpg"
            val number = places?.get(i) ?: (i + 1).takeIf { urls.size > 1 }
            val name = if (number != null) "$title $number.$ext" else "$title.$ext"
            File(workDir, name).also { file.renameTo(it) }
        }
    }

    /**
     * Re-encodes the saved video at [DownloadRequest.url] (a content URI) to
     * fit [spec]; returns `<name>.mp4`. FFmpeg can't read content URIs, so
     * the video is copied into [workDir] first.
     */
    private fun fitVideo(task: DownloadTask, spec: FitSpec, workDir: File): File {
        val input = File(workDir, "input")
        val source = contentResolver.openInputStream(Uri.parse(task.request.url))
            ?: throw FileNotFoundException(task.request.url)
        source.use { from -> input.outputStream().use { from.copyTo(it) } }

        val name = safeFileName(spec.name).ifBlank { "video" }
        val output = File(workDir, "$name.mp4")
        try {
            VideoFitter(this).fit(
                input,
                output,
                spec,
                onStart = { process ->
                    processes[task.id] = process
                    // Cancelled before FFmpeg started.
                    if (task.cancelRequested) process.destroy()
                },
                onProgress = { percent ->
                    task.percent = percent
                    publish(task)
                },
            )
        } finally {
            processes.remove(task.id)
            input.delete()
        }
        return output
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
        targetDir = getStringExtra(EXTRA_TARGET_DIR) ?: return null,
        title = getStringExtra(EXTRA_TITLE),
        items = getIntArrayExtra(EXTRA_ITEMS)?.toList()?.takeIf { it.isNotEmpty() },
        imageUrls = getStringArrayListExtra(EXTRA_IMAGE_URLS)?.takeIf { it.isNotEmpty() },
        options = getStringArrayListExtra(EXTRA_OPTIONS).orEmpty(),
        playlist = getBooleanExtra(EXTRA_PLAYLIST, false),
        archive = getBooleanExtra(EXTRA_ARCHIVE, false),
        fileName = getStringExtra(EXTRA_FILE_NAME),
        fit = getStringExtra(EXTRA_FIT_NAME)?.let { name ->
            FitSpec(
                targetBytes = getLongExtra(EXTRA_FIT_TARGET_BYTES, 0),
                durationMs = getLongExtra(EXTRA_FIT_DURATION_MS, 0),
                videoKbps = getIntExtra(EXTRA_FIT_VIDEO_KBPS, 0),
                audioKbps = getIntExtra(EXTRA_FIT_AUDIO_KBPS, 0),
                maxShortSide = getIntExtra(EXTRA_FIT_MAX_SHORT_SIDE, 0),
                name = name,
            )
        },
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
        private const val EXTRA_TARGET_DIR = "targetDir"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ITEMS = "items"
        private const val EXTRA_IMAGE_URLS = "imageUrls"
        private const val EXTRA_OPTIONS = "options"
        private const val EXTRA_PLAYLIST = "playlist"
        private const val EXTRA_ARCHIVE = "archive"
        private const val EXTRA_FILE_NAME = "fileName"
        private const val EXTRA_FIT_TARGET_BYTES = "fitTargetBytes"
        private const val EXTRA_FIT_DURATION_MS = "fitDurationMs"
        private const val EXTRA_FIT_VIDEO_KBPS = "fitVideoKbps"
        private const val EXTRA_FIT_AUDIO_KBPS = "fitAudioKbps"
        private const val EXTRA_FIT_MAX_SHORT_SIDE = "fitMaxShortSide"
        private const val EXTRA_FIT_NAME = "fitName"

        private const val TAG = "DownloadService"

        private val ARCHIVE_LOCK = Any()
        private const val MAX_PARALLEL = 2
        private const val EVENT_INTERVAL_MS = 250L

        /** `startDownload` selector for every item of the link (see CLAUDE.md). */
        private const val FORMAT_POST = "post"

        /** `startDownload` selector for photos Dart found (see CLAUDE.md). */
        private const val FORMAT_IMAGES = "images"
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "heic", "avif")
        private const val NO_FORMATS = "No video formats found"

        // "[download] Downloading item 3 of 19"
        private val ITEM = Regex("""Downloading item (\d+) of (\d+)""")

        private fun safeFileName(name: String) =
            name.replace(Regex("""[\\/:*?"<>|\p{Cntrl}]"""), "_").trim().take(120)

        // "[download]  45.3% of ~ 10.00MiB at    2.31MiB/s ETA 00:03"
        private val SPEED = Regex("""\bat\s+(\S+/s)""")

        /** [bytesPerSecond] the way yt-dlp writes it, e.g. `2.31MiB/s`. */
        private fun formatSpeed(bytesPerSecond: Float): String = when {
            bytesPerSecond >= 1024 * 1024 -> "%.2fMiB/s".format(Locale.ROOT, bytesPerSecond / (1024 * 1024))
            else -> "%.2fKiB/s".format(Locale.ROOT, bytesPerSecond / 1024)
        }

        /** Ids queued or running in this process. */
        private val activeIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Must be called while the app is in the foreground. */
        fun start(context: Context, request: DownloadRequest) {
            val intent = Intent(context, DownloadService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_ID, request.id)
                .putExtra(EXTRA_URL, request.url)
                .putExtra(EXTRA_FORMAT_ID, request.formatId)
                .putExtra(EXTRA_TARGET_DIR, request.targetDir)
                .putExtra(EXTRA_TITLE, request.title)
                .putExtra(EXTRA_ITEMS, request.items?.toIntArray())
                .putStringArrayListExtra(EXTRA_IMAGE_URLS, request.imageUrls?.let(::ArrayList))
                .putStringArrayListExtra(EXTRA_OPTIONS, ArrayList(request.options))
                .putExtra(EXTRA_PLAYLIST, request.playlist)
                .putExtra(EXTRA_ARCHIVE, request.archive)
                .putExtra(EXTRA_FILE_NAME, request.fileName)
            request.fit?.let { fit ->
                intent.putExtra(EXTRA_FIT_TARGET_BYTES, fit.targetBytes)
                    .putExtra(EXTRA_FIT_DURATION_MS, fit.durationMs)
                    .putExtra(EXTRA_FIT_VIDEO_KBPS, fit.videoKbps)
                    .putExtra(EXTRA_FIT_AUDIO_KBPS, fit.audioKbps)
                    .putExtra(EXTRA_FIT_MAX_SHORT_SIDE, fit.maxShortSide)
                    .putExtra(EXTRA_FIT_NAME, fit.name)
            }
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

    /** Set by a cancel, so a process it kills counts as cancelled, not failed. */
    @Volatile var cancelRequested = false

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
