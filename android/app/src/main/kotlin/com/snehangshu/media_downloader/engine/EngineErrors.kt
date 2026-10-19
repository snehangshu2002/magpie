package com.snehangshu.media_downloader.engine

import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException

/**
 * Error codes sent to Dart as `PlatformException.code`.
 * Keep in sync with `NativeErrorCode` in platform_failure.dart and CLAUDE.md.
 */
internal object EngineErrors {
    const val UNSUPPORTED_URL = "UNSUPPORTED_URL"
    const val NETWORK = "NETWORK"
    const val ENGINE = "ENGINE"
    const val STORAGE = "STORAGE"
    const val CANCELLED = "CANCELLED"
    const val UNKNOWN = "UNKNOWN"

    data class Error(val code: String, val message: String?)

    // Substrings of yt-dlp's "ERROR: ..." output that indicate a connectivity problem.
    private val networkHints = listOf(
        "Unable to download webpage",
        "Failed to resolve",
        "Temporary failure in name resolution",
        "Network is unreachable",
        "timed out",
    )

    fun from(e: Exception): Error = when (e) {
        is YoutubeDL.CanceledException, is InterruptedException -> Error(CANCELLED, e.message)
        is YoutubeDLException -> Error(classify(e.message.orEmpty()), e.message)
        else -> Error(UNKNOWN, e.message)
    }

    private fun classify(message: String): String = when {
        message.contains("Unsupported URL", ignoreCase = true) -> UNSUPPORTED_URL
        networkHints.any { message.contains(it, ignoreCase = true) } -> NETWORK
        else -> ENGINE
    }
}
