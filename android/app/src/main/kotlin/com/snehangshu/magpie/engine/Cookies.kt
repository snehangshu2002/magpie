package com.snehangshu.magpie.engine

import android.content.Context
import android.net.Uri
import android.webkit.CookieManager
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File

/**
 * Sign-ins the user made in [SignInActivity], kept as a Netscape cookie file
 * that yt-dlp reads (and updates) with `--cookies`. yt-dlp only sends a
 * site its own cookies, so the file is passed on every run.
 */
internal object Cookies {
    private const val HEADER = "# Netscape HTTP Cookie File"

    // Far in the future: WebView doesn't tell when a cookie expires.
    private const val EXPIRES = "2147483647"

    private val lock = Any()

    private fun file(context: Context) = File(context.noBackupFilesDir, "cookies.txt")

    /** Adds `--cookies` when the user signed in to any site. */
    fun apply(context: Context, request: YoutubeDLRequest) {
        val file = file(context)
        if (file.exists()) request.addOption("--cookies", file.absolutePath)
    }

    /** Sites with saved cookies, e.g. `instagram.com`. */
    fun sites(context: Context): List<String> = synchronized(lock) {
        lines(context).map { it.split('\t').first().trimStart('.') }.distinct().sorted()
    }

    /**
     * Copies the WebView's cookies for [url]'s site into the file, replacing
     * what was kept for it before. Returns the number of cookies saved.
     */
    fun saveFromWebView(context: Context, url: String): Int = synchronized(lock) {
        val manager = CookieManager.getInstance()
        manager.flush()
        val site = siteOf(url) ?: return 0
        val raw = manager.getCookie("https://$site") ?: manager.getCookie(url)
        val cookies = raw.orEmpty().split(';').mapNotNull { pair ->
            val name = pair.substringBefore('=').trim()
            if (name.isEmpty() || !pair.contains('=')) return@mapNotNull null
            listOf(".$site", "TRUE", "/", "TRUE", EXPIRES, name, pair.substringAfter('=').trim())
                .joinToString("\t")
        }
        write(context, lines(context).filterNot { it.belongsTo(site) } + cookies)
        cookies.size
    }

    /**
     * Forgets [site]'s cookies. The WebView forgets every site's: it can't
     * drop one site's HttpOnly cookies, and the file still holds the others.
     */
    fun remove(context: Context, site: String) = synchronized(lock) {
        write(context, lines(context).filterNot { it.belongsTo(site) })
        CookieManager.getInstance().apply {
            removeAllCookies(null)
            flush()
        }
    }

    /** `instagram.com` for `https://www.instagram.com/accounts/login`. */
    fun siteOf(url: String): String? {
        val host = Uri.parse(url).host?.lowercase() ?: return null
        return host.removePrefix("www.").removePrefix("m.").removePrefix("mobile.")
    }

    private fun String.belongsTo(site: String) =
        split('\t').first().trimStart('.').let { it == site || it.endsWith(".$site") }

    private fun lines(context: Context): List<String> {
        val file = file(context)
        if (!file.exists()) return emptyList()
        return file.readLines().filter { it.isNotBlank() && !it.startsWith("#") }
    }

    private fun write(context: Context, lines: List<String>) {
        val file = file(context)
        if (lines.isEmpty()) {
            file.delete()
            return
        }
        file.writeText((listOf(HEADER) + lines).joinToString("\n", postfix = "\n"))
    }
}
