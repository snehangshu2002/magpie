package com.snehangshu.magpie.storage

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** Saving to shared storage failed; reported to Dart as `STORAGE`. */
class StorageException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * Copies finished downloads into shared storage so they show up in the file
 * manager and gallery. Uses MediaStore on Android 10+, and the public
 * directory plus a media scan before that.
 */
object MediaStoreSaver {
    /**
     * Saves [file] under [relativeDir] (e.g. `Download/Magpie/YouTube`) and
     * returns its content URI. Runs blocking IO; call it off the main thread.
     */
    suspend fun save(context: Context, file: File, relativeDir: String): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToMediaStore(context, file, relativeDir)
        } else {
            saveToPublicDir(context, file, relativeDir)
        }

    fun mimeTypeOf(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())
            ?: "application/octet-stream"

    /**
     * The extension matching [file]'s content when it is an image, else null.
     * yt-dlp names images after their URL, which can be wrong.
     */
    fun imageExtensionOf(file: File): String? {
        val head = ByteArray(12)
        val read = file.inputStream().use { it.read(head) }
        if (read < head.size) return null
        fun ascii(from: Int, length: Int) = String(head, from, length, Charsets.US_ASCII)
        return when {
            head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte() && head[2] == 0xFF.toByte() -> "jpg"
            head[0] == 0x89.toByte() && ascii(1, 3) == "PNG" -> "png"
            ascii(0, 4) == "RIFF" && ascii(8, 4) == "WEBP" -> "webp"
            ascii(0, 3) == "GIF" -> "gif"
            ascii(4, 4) == "ftyp" && ascii(8, 4) in HEIF_BRANDS -> "heic"
            else -> null
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveToMediaStore(context: Context, file: File, relativeDir: String): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeOf(file))
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDir.trimEnd('/') + "/")
            // Hidden from other apps until the copy is complete.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw StorageException("MediaStore refused to create ${file.name}")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw StorageException("Couldn't open $uri for writing")
            output.use { out -> file.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e as? StorageException ?: StorageException("Couldn't save ${file.name}", e)
        }
    }

    // Android 7–9: needs WRITE_EXTERNAL_STORAGE, requested before the download starts.
    @Suppress("DEPRECATION")
    private suspend fun saveToPublicDir(context: Context, file: File, relativeDir: String): Uri {
        val target = try {
            val dir = File(Environment.getExternalStorageDirectory(), relativeDir)
            if (!dir.isDirectory && !dir.mkdirs()) {
                throw StorageException("Couldn't create $dir")
            }
            file.copyTo(uniqueFile(dir, file.name))
        } catch (e: StorageException) {
            throw e
        } catch (e: Exception) {
            throw StorageException("Couldn't save ${file.name}", e)
        }
        val scanned = withTimeoutOrNull(SCAN_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(target.absolutePath),
                    arrayOf(mimeTypeOf(target)),
                ) { _, uri -> continuation.resume(uri) }
            }
        }
        // The file is saved either way; without a scan result it only lacks a content URI.
        return scanned ?: Uri.fromFile(target)
    }

    /** `name.ext`, or `name (1).ext`, `name (2).ext`… if taken; MediaStore does this itself. */
    private fun uniqueFile(dir: File, name: String): File {
        val base = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
        return generateSequence(0) { it + 1 }
            .map { n -> File(dir, if (n == 0) name else "$base ($n)$ext") }
            .first { !it.exists() }
    }

    private const val SCAN_TIMEOUT_MS = 10_000L
    private val HEIF_BRANDS = setOf("heic", "heix", "mif1", "msf1")
}
