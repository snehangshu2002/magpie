package com.snehangshu.magpie.engine

import android.content.Context
import com.yausername.aria2c.Aria2c
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** yt-dlp, FFmpeg and aria2c setup shared by [YtDlpBridge] and [DownloadService]. */
internal object Engine {
    private val initMutex = Mutex()
    private val updateMutex = Mutex()
    private var initialized = false

    /** Unpacks Python, yt-dlp, FFmpeg and aria2c on first use; later calls return at once. */
    suspend fun ensureInitialized(context: Context) = initMutex.withLock {
        if (!initialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            FFmpeg.getInstance().init(context.applicationContext)
            Aria2c.getInstance().init(context.applicationContext)
            initialized = true
        }
    }

    /**
     * Updates yt-dlp from [channel]. One at a time: the launch-time update and
     * one started from Settings would otherwise replace the same file.
     */
    suspend fun update(context: Context, channel: YoutubeDL.UpdateChannel) =
        updateMutex.withLock {
            ensureInitialized(context)
            YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext, channel)
        }
}
