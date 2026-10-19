package com.snehangshu.magpie.storage

import android.app.RecoverableSecurityException
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.engine.EngineErrors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Native side of the `app/storage` channel (see CLAUDE.md): looks up, opens,
 * shares and deletes files the app saved to shared storage.
 */
class StorageBridge(
    private val context: Context,
    private val host: ActivityHost,
) : MethodChannel.MethodCallHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "queryFiles" -> respond(result) {
                call.argument<List<String>>("uris").orEmpty().mapNotNull { query(Uri.parse(it)) }
            }

            "thumbnail" -> respond(result) {
                thumbnail(Uri.parse(call.requireString("uri")), call.argument<Int>("size") ?: 256)
            }

            "openFile" -> respond(result) {
                val uri = requireExisting(call.requireString("uri"))
                launch(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, call.argument<String>("mimeType"))
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                )
                null
            }

            "shareFile" -> respond(result) {
                val uri = requireExisting(call.requireString("uri"))
                val send = Intent(Intent.ACTION_SEND)
                    .setType(call.argument<String>("mimeType") ?: "*/*")
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                launch(Intent.createChooser(send, call.argument<String>("title")))
                null
            }

            "deleteFile" -> respond(result) { delete(Uri.parse(call.requireString("uri"))) }

            else -> result.notImplemented()
        }
    }

    /** `{uri, name, size, mimeType}`, or null if the file is gone. */
    private fun query(uri: Uri): Map<String, Any?>? {
        if (uri.scheme == "file") {
            val file = File(uri.path ?: return null)
            if (!file.isFile) return null
            return mapOf(
                "uri" to uri.toString(),
                "name" to file.name,
                "size" to file.length(),
                "mimeType" to MediaStoreSaver.mimeTypeOf(file),
            )
        }
        val columns = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        return try {
            context.contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                mapOf(
                    "uri" to uri.toString(),
                    "name" to cursor.getString(0),
                    "size" to cursor.getLong(1).takeIf { it > 0 },
                    "mimeType" to cursor.getString(2),
                )
            }
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /** A JPEG preview of a video or image (or an audio file's cover art); null if there is none. */
    private fun thumbnail(uri: Uri, size: Int): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || uri.scheme != "content") return null
        val bitmap = try {
            context.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } catch (_: Exception) {
            return null
        }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    /**
     * Deletes the file. Files the app no longer owns (e.g. after a reinstall)
     * need the user's OK; returns false if they decline.
     */
    private suspend fun delete(uri: Uri): Boolean {
        if (uri.scheme == "file") return File(uri.path ?: return true).let { !it.exists() || it.delete() }
        val resolver = context.contentResolver
        return try {
            resolver.delete(uri, null, null) > 0 || query(uri) == null
        } catch (e: SecurityException) {
            val request = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    MediaStore.createDeleteRequest(resolver, listOf(uri)).intentSender
                Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException ->
                    e.userAction.actionIntent.intentSender
                else -> throw StorageException("Not allowed to delete $uri", e)
            }
            if (!host.confirm(request)) return false
            // Android 11+ deletes as part of the prompt; Android 10 only grants access.
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ||
                resolver.delete(uri, null, null) > 0
        }
    }

    private fun requireExisting(uri: String): Uri =
        Uri.parse(uri).also { if (query(it) == null) throw FileNotFoundException(uri) }

    private suspend fun launch(intent: Intent) = withContext(Dispatchers.Main) {
        try {
            host.launch(intent)
        } catch (e: ActivityNotFoundException) {
            throw NoAppException(e)
        }
    }

    /** Runs [block] on the IO dispatcher and replies with its value or a typed error. */
    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(withContext(Dispatchers.IO) { block() })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = EngineErrors.from(e)
                result.error(error.code, error.message, null)
            }
        }
    }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    private companion object {
        const val CHANNEL = "app/storage"
    }
}

/** No installed app can open or share the file; reported as `NO_APP`. */
class NoAppException(cause: Throwable) : Exception(cause.message, cause)
