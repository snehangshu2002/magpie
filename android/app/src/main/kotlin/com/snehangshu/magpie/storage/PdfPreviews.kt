package com.snehangshu.magpie.storage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Pictures of a PDF's pages for the PDF tools' preview (`pdfPage`). The PDF
 * last asked for stays open, copied once into the cache (without security
 * when it has a password), so a grid of pages doesn't copy it for each one.
 */
internal class PdfPreviews(private val context: Context) {
    // PdfRenderer allows one open page at a time, and calls arrive at once.
    private val mutex = Mutex()
    private val dir = File(context.cacheDir, "pdf-preview")
    private var key: Pair<String, String?>? = null
    private var renderer: PdfRenderer? = null

    /** `{bytes, width, height}`: page [page] (1-based) as a JPEG [size] px on its longest side; its size in points. */
    suspend fun page(uri: Uri, password: String?, page: Int, size: Int): Map<String, Any?> = mutex.withLock {
        val renderer = open(uri, password)
        require(page in 1..renderer.pageCount) { "No page $page" }
        val side = size.coerceIn(16, PdfEditor.MAX_RENDER_SIDE).toFloat()
        var width = 0
        var height = 0
        val bitmap = try {
            PdfEditor.renderPage(renderer, page - 1) { w, h ->
                width = w
                height = h
                side / maxOf(w, h)
            }
        } catch (e: OutOfMemoryError) {
            throw StorageException("The page is too big to show", e)
        }
        val bytes = ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            bitmap.recycle()
            out.toByteArray()
        }
        mapOf("bytes" to bytes, "width" to width, "height" to height)
    }

    /** Closes the open PDF and deletes its copy, which may be a protected PDF without its password. */
    fun close() {
        renderer?.close()
        renderer = null
        key = null
        dir.deleteRecursively()
    }

    private fun open(uri: Uri, password: String?): PdfRenderer {
        val wanted = uri.toString() to password
        renderer?.let { if (key == wanted) return it }
        close()
        dir.mkdirs()
        return PdfEditor.openRenderer(PdfEditor(context, dir).plainCopy(uri, password)).also {
            renderer = it
            key = wanted
        }
    }
}
