package com.snehangshu.magpie.engine

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** yt-dlp and FFmpeg setup shared by [YtDlpBridge] and [DownloadService]. */
internal object Engine {
    private val initMutex = Mutex()
    private var initialized = false

    /** Unpacks Python, yt-dlp and FFmpeg on first use; later calls return at once. */
    suspend fun ensureInitialized(context: Context) = initMutex.withLock {
        if (!initialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            FFmpeg.getInstance().init(context.applicationContext)
            initialized = true
        }
    }
}
