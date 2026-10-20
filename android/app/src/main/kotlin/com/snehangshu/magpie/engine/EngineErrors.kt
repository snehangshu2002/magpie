package com.snehangshu.magpie.engine

import com.snehangshu.magpie.storage.NoAppException
import com.snehangshu.magpie.storage.StorageException
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import java.io.FileNotFoundException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

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
    const val NOT_FOUND = "NOT_FOUND"
    const val NO_APP = "NO_APP"
    const val TOO_LARGE = "TOO_LARGE"
    const val ENCODE = "ENCODE"
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
        // The updater wraps its HTTP failure, e.g. when api.github.com is unreachable.
        is YoutubeDLException -> Error(
            if (e.cause.isConnectivity()) NETWORK else classify(e.message.orEmpty()),
            e.message,
        )
        is StorageException -> Error(STORAGE, e.message)
        is FitTooLargeException -> Error(TOO_LARGE, e.message)
        is EncodeException -> Error(ENCODE, e.message)
        is ImageFetcher.CancelledException -> Error(CANCELLED, e.message)
        is NotAnImageException -> Error(UNSUPPORTED_URL, e.message)
        is HttpStatusException -> Error(NETWORK, e.message)
        is FileNotFoundException -> Error(NOT_FOUND, e.message)
        is NoAppException -> Error(NO_APP, e.message)
        // Plain HTTP image downloads (`images` jobs).
        is SocketException, is UnknownHostException, is SocketTimeoutException -> Error(NETWORK, e.message)
        else -> Error(UNKNOWN, e.message)
    }

    private fun Throwable?.isConnectivity() =
        this is SocketException || this is UnknownHostException || this is SocketTimeoutException

    private fun classify(message: String): String = when {
        message.contains("Unsupported URL", ignoreCase = true) -> UNSUPPORTED_URL
        networkHints.any { message.contains(it, ignoreCase = true) } -> NETWORK
        else -> ENGINE
    }
}
