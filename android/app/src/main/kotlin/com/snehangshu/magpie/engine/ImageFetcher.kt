package com.snehangshu.magpie.engine

import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URI
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
     * once [isCancelled] is true. [options] are the job's yt-dlp arguments:
     * their last `--proxy` and `--user-agent` apply here too.
     */
    fun fetch(
        url: String,
        to: File,
        options: List<String>,
        isCancelled: () -> Boolean,
        onProgress: (read: Long, total: Long?) -> Unit,
    ) {
        // shortcut: `-4` isn't applied, HttpURLConnection has no DNS hook
        // (connecting to the IPv4 literal breaks TLS SNI); use a client with
        // one (OkHttp's Dns) if IPv6-broken networks fail photo downloads.
        val connection = URL(url).openConnection(proxyOf(valueOf(options, "--proxy"))) as HttpURLConnection
        try {
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", valueOf(options, "--user-agent") ?: USER_AGENT)
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

    private fun valueOf(options: List<String>, name: String): String? =
        options.lastIndexOf(name).takeIf { it >= 0 }?.let { options.getOrNull(it + 1) }

    /**
     * The proxy yt-dlp would use for [url] (`--proxy`); none when unset or
     * empty. shortcut: proxy credentials aren't sent and an https:// proxy is
     * spoken to in plain HTTP; add an Authenticator / TLS if users need them.
     */
    private fun proxyOf(url: String?): Proxy {
        val uri = url?.trim()?.takeIf { it.isNotEmpty() }?.let(::URI) ?: return Proxy.NO_PROXY
        val type = if (uri.scheme.orEmpty().startsWith("socks")) Proxy.Type.SOCKS else Proxy.Type.HTTP
        val port = uri.port.takeIf { it > 0 } ?: if (type == Proxy.Type.SOCKS) 1080 else 80
        return Proxy(type, InetSocketAddress.createUnresolved(uri.host, port))
    }

    /** A cancel stopped the download. */
    class CancelledException : IOException("Cancelled")
}
