package com.snehangshu.magpie.storage

import android.app.RecoverableSecurityException
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.engine.EngineErrors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
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
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var channel: MethodChannel? = null
    private var changesChannel: EventChannel? = null

    // Tells Dart that shared storage changed (a file added, edited or deleted
    // by any app), so the Library can re-check its files. Set while Dart listens.
    private var observer: ContentObserver? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
        changesChannel = EventChannel(messenger, CHANGES_CHANNEL).also { it.setStreamHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        changesChannel?.setStreamHandler(null)
        channel = null
        changesChannel = null
        onCancel(null)
        scope.cancel()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) = events.success(null)
        }.also {
            context.contentResolver.registerContentObserver(
                MediaStore.Files.getContentUri("external"),
                true,
                it,
            )
        }
    }

    override fun onCancel(arguments: Any?) {
        observer?.let(context.contentResolver::unregisterContentObserver)
        observer = null
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

            "shareFiles" -> respond(result) {
                // Files deleted meanwhile are left out; the Library drops them on its next sync.
                val uris = call.requireUris().filter { query(it) != null }
                if (uris.isEmpty()) throw FileNotFoundException("None of the files exist")
                val send = if (uris.size == 1) {
                    Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.single())
                } else {
                    Intent(Intent.ACTION_SEND_MULTIPLE)
                        .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                }
                send.setType(call.argument<String>("mimeType") ?: "*/*")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                // The read grant travels with ClipData through the chooser.
                send.clipData = ClipData.newRawUri(null, uris.first()).apply {
                    uris.drop(1).forEach { addItem(ClipData.Item(it)) }
                }
                launch(Intent.createChooser(send, call.argument<String>("title")))
                null
            }

            "deleteFiles" -> respond(result) { delete(call.requireUris()) }

            "pickFolder" -> respond(result) { pickFolder() }

            else -> result.notImplemented()
        }
    }

    /**
     * `{uri, name, size, mimeType}`, or null if the file is gone. A file in
     * the system trash (deleted in Files or Photos on Android 11+) counts as
     * gone: a query by its URI still finds it for 30 days.
     */
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
        val trashable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        val columns = listOfNotNull(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            if (trashable) MediaStore.MediaColumns.IS_TRASHED else null,
        ).toTypedArray()
        return try {
            context.contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst() || !canOpen(uri)) return null
                if (trashable && cursor.getInt(3) == 1) return null
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

    /**
     * Some file managers delete the file itself, and MediaStore keeps its row
     * until the next scan; only a file that opens is really there.
     */
    private fun canOpen(uri: Uri): Boolean = try {
        context.contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
    } catch (_: FileNotFoundException) {
        false
    } catch (_: SecurityException) {
        true // There, just not ours to read.
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
    /**
     * Deletes [uris] and returns those now gone. Files the app no longer owns
     * (e.g. after a reinstall) need the user's OK: one system prompt for all
     * of them on Android 11+, one per file on Android 10. Declined ones are
     * left out of the result.
     */
    private suspend fun delete(uris: List<Uri>): List<String> {
        val resolver = context.contentResolver
        val gone = mutableListOf<Uri>()
        val needConsent = mutableListOf<Uri>()
        for (uri in uris) {
            if (uri.scheme == "file") {
                val file = File(uri.path ?: continue)
                if (!file.exists() || file.delete()) gone += uri
                continue
            }
            try {
                if (resolver.delete(uri, null, null) > 0 || query(uri) == null) gone += uri
            } catch (e: SecurityException) {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> { needConsent += uri }
                    // Android 10 only grants access; delete again once allowed.
                    Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException ->
                        if (host.confirm(e.userAction.actionIntent.intentSender) &&
                            resolver.delete(uri, null, null) > 0
                        ) {
                            gone += uri
                        }
                    else -> throw StorageException("Not allowed to delete $uri", e)
                }
            }
        }
        // Android 11+ deletes as part of the prompt.
        if (needConsent.isNotEmpty() &&
            host.confirm(MediaStore.createDeleteRequest(resolver, needConsent).intentSender)
        ) {
            gone += needConsent
        }
        return gone.map(Uri::toString)
    }

    private fun requireExisting(uri: String): Uri =
        Uri.parse(uri).also { if (query(it) == null) throw FileNotFoundException(uri) }

    /**
     * Android's folder picker, opened at Download. Returns the chosen folder's
     * document id (`primary:Download/Videos`), or null if the user backed out;
     * Dart decides whether downloads can go there.
     */
    private suspend fun pickFolder(): String? {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_DOCUMENTS, "primary:Download"),
            )
        }
        val data = try {
            host.pick(intent)
        } catch (e: ActivityNotFoundException) {
            throw NoAppException(e)
        }
        return data?.data?.let(DocumentsContract::getTreeDocumentId)
    }

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

    private fun MethodCall.requireUris(): List<Uri> =
        (argument<List<String>>("uris") ?: throw IllegalArgumentException("Missing argument: uris"))
            .map(Uri::parse)

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    private companion object {
        const val CHANNEL = "app/storage"
        const val CHANGES_CHANNEL = "app/storage/changes"
        const val EXTERNAL_STORAGE_DOCUMENTS = "com.android.externalstorage.documents"
    }
}

/** No installed app can open or share the file; reported as `NO_APP`. */
class NoAppException(cause: Throwable) : Exception(cause.message, cause)
