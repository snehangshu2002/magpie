package com.snehangshu.magpie.engine

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** yt-dlp and FFmpeg setup shared by [YtDlpBridge] and [DownloadService]. */
internal object Engine {
    private val initMutex = Mutex()
    private val updateMutex = Mutex()
    private var initialized = false

    /** Unpacks Python, yt-dlp and FFmpeg on first use; later calls return at once. */
    suspend fun ensureInitialized(context: Context) = initMutex.withLock {
        if (!initialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            FFmpeg.getInstance().init(context.applicationContext)
            initialized = true
        }
    }

    /**
     * Updates yt-dlp from [channel]. One at a time: the launch-time update and
     * one started from Settings would otherwise replace the same file.
     */
    // shortcut: youtubedl-android fetches the update itself, so Settings'
    // proxy, IPv4 and browser identity don't apply here; pass them through
    // if the library ever takes a proxy.
    suspend fun update(context: Context, channel: YoutubeDL.UpdateChannel) =
        updateMutex.withLock {
            ensureInitialized(context)
            YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext, channel)
        }
}
