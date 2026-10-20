package com.snehangshu.magpie.engine

import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** The server answered an image request with an error status. */
class HttpStatusException(val status: Int) : IOException("HTTP $status")

/** The URL served something other than an image. */
class NotAnImageException(message: String) : IOException(message)

/**
 * Downloads photos by plain HTTP for `images` jobs, whose full-size URLs
 * Dart worked out (X, Reddit, links to an image). yt-dlp doesn't save these.
 */
internal object ImageFetcher {
    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 30_000
    private const val USER_AGENT = "Mozilla/5.0 (Linux; Android 14) Magpie"

    /**
     * Writes the image at [url] to [to]. [onProgress] gets the bytes read so
     * far and the total, when the server says. Stops with [CancelledException]
     * once [isCancelled] is true.
     */
    fun fetch(
        url: String,
        to: File,
        isCancelled: () -> Boolean,
        onProgress: (read: Long, total: Long?) -> Unit,
    ) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", USER_AGENT)
            connection.setRequestProperty("Accept", "*/*")
            when (val status = connection.responseCode) {
                in 200..299 -> Unit
                404, 410 -> throw FileNotFoundException(url)
                else -> throw HttpStatusException(status)
            }
            val type = connection.contentType.orEmpty()
            if (type.isNotEmpty() && !type.startsWith("image/") &&
                !type.startsWith("application/octet-stream")
            ) {
                throw NotAnImageException("$url is $type")
            }
            val total = connection.contentLengthLong.takeIf { it > 0 }
            connection.inputStream.use { input ->
                to.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var read = 0L
                    while (true) {
                        if (isCancelled()) throw CancelledException()
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        read += n
                        onProgress(read, total)
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    /** A cancel stopped the download. */
    class CancelledException : IOException("Cancelled")
}
