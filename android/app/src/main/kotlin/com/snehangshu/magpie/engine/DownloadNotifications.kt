package com.snehangshu.magpie.engine

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.snehangshu.magpie.MainActivity
import com.snehangshu.magpie.R

/**
 * The ongoing progress notification that keeps [DownloadService] in the
 * foreground, plus one notification per finished download.
 * Posting is a no-op when the user has denied POST_NOTIFICATIONS.
 */
internal class DownloadNotifications(private val context: Context) {
    private val manager = NotificationManagerCompat.from(context)
    private var lastProgressAt = 0L

    init {
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName(context.getString(R.string.download_channel_name))
                .setDescription(context.getString(R.string.download_channel_description))
                .build(),
        )
    }

    fun progress(tasks: Collection<DownloadTask>): Notification {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openApp())
        val single = tasks.singleOrNull()
        when {
            tasks.isEmpty() -> builder
                .setContentTitle(context.getString(R.string.download_preparing))
                .setProgress(0, 0, true)

            single != null -> builder
                .setContentTitle(single.request.title ?: context.getString(R.string.download_untitled))
                .setContentText(statusOf(single))
                .setProgress(100, single.percent.toInt(), single.state == DownloadService.STATE_QUEUED)
                .addAction(0, context.getString(R.string.download_cancel), cancel(single.id))

            else -> builder
                .setContentTitle(context.getString(R.string.download_many, tasks.size))
                .setContentText(tasks.joinToString { it.request.title ?: context.getString(R.string.download_untitled) })
                .setProgress(100, tasks.map { it.percent }.average().toInt(), false)
        }
        return builder.build()
    }

    /** Refreshes the ongoing notification, at most once a second unless [force]d. */
    fun updateProgress(tasks: Collection<DownloadTask>, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastProgressAt < PROGRESS_INTERVAL_MS) return
        lastProgressAt = now
        post(FOREGROUND_ID, progress(tasks))
    }

    /** Tells the user a download saved (tap to open) or failed; cancelled ones stay quiet. */
    fun result(task: DownloadTask) {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(task.request.title ?: context.getString(R.string.download_untitled))
            .setAutoCancel(true)
        when (task.state) {
            DownloadService.STATE_SAVED -> builder
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentText(context.getString(R.string.download_saved_to, task.request.targetDir))
                .setContentIntent(openFile(task) ?: openApp())

            DownloadService.STATE_FAILED -> builder
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentText(context.getString(R.string.download_failed))
                .setContentIntent(openApp())

            else -> return
        }
        post(task.id.hashCode(), builder.build())
    }

    private fun statusOf(task: DownloadTask): String = when (task.state) {
        DownloadService.STATE_QUEUED -> context.getString(R.string.download_waiting)
        DownloadService.STATE_MERGING -> context.getString(R.string.download_finishing)
        else -> task.speed?.let {
            context.getString(R.string.download_percent_speed, task.percent.toInt(), it)
        } ?: context.getString(R.string.download_percent, task.percent.toInt())
    }

    private fun post(id: Int, notification: Notification) {
        if (manager.areNotificationsEnabled()) {
            try {
                manager.notify(id, notification)
            } catch (_: SecurityException) {
                // Permission revoked between the check and the call.
            }
        }
    }

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun openFile(task: DownloadTask): PendingIntent? {
        val uri = task.filePath?.let(Uri::parse)?.takeIf { it.scheme == "content" } ?: return null
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, task.mimeType)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            task.id.hashCode(),
            view,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun cancel(id: String): PendingIntent = PendingIntent.getService(
        context,
        id.hashCode(),
        Intent(context, DownloadService::class.java)
            .setAction(DownloadService.ACTION_CANCEL)
            .putExtra(DownloadService.EXTRA_ID, id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        const val FOREGROUND_ID = 1
        private const val CHANNEL_ID = "downloads"
        private const val PROGRESS_INTERVAL_MS = 1_000L
    }
}
