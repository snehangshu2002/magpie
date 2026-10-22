package com.snehangshu.magpie.updater

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.engine.EngineErrors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The downloaded APK isn't the file the release lists; reported as `NETWORK`. */
class ChecksumException(message: String) : IOException(message)

/**
 * `app/updater`: the installed version and ABIs, so Dart can tell whether a
 * GitHub release is newer and which APK fits; a place for Dart to download
 * that APK, and handing it to Android's installer; and opening a link.
 */
class UpdaterBridge(
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
            "appInfo" -> result.success(
                mapOf(
                    "version" to context.packageManager
                        .getPackageInfo(context.packageName, 0).versionName,
                    "abis" to Build.SUPPORTED_ABIS.toList(),
                ),
            )

            "openUrl" -> try {
                host.launch(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                result.success(null)
            } catch (e: ActivityNotFoundException) {
                result.error(EngineErrors.NO_APP, e.message, null)
            }

            "prepareApk" -> respond(result) { prepareApk(call.requireString("name")) }

            "installApk" -> respond(result) {
                installApk(File(call.requireString("path")), call.argument<String>("sha256"))
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Where Dart should download update APK [name]: in the cache folder the
     * installer can read through [FileProvider]. Earlier downloads there are
     * deleted.
     */
    private fun prepareApk(name: String): String {
        val dir = updatesDir()
        dir.listFiles()?.forEach(File::delete)
        val safeName = name.replace(Regex("""[^A-Za-z0-9._-]"""), "_")
        return File(dir, safeName).absolutePath
    }

    /**
     * Checks [apk] against the release's [sha256] (when GitHub lists one) and
     * opens Android's installer for it, which asks the user to confirm (and,
     * the first time, to allow installs from Magpie).
     */
    private suspend fun installApk(apk: File, sha256: String?) {
        if (!apk.isFile || apk.parentFile?.canonicalPath != updatesDir().canonicalPath) {
            throw FileNotFoundException(apk.path)
        }
        if (sha256 != null && !sha256.equals(sha256Of(apk), ignoreCase = true)) {
            apk.delete()
            throw ChecksumException("Checksum mismatch for ${apk.name}")
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        withContext(Dispatchers.Main) { host.launch(intent) }
    }

    private fun sha256Of(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun updatesDir() = File(context.cacheDir, "updates").apply { mkdirs() }

    /** Runs [block] on the IO dispatcher and replies with its value or a typed error. */
    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(withContext(Dispatchers.IO) { block() })
            } catch (e: CancellationException) {
                throw e
            } catch (e: ActivityNotFoundException) {
                result.error(EngineErrors.NO_APP, e.message, null)
            } catch (e: ChecksumException) {
                result.error(EngineErrors.NETWORK, e.message, null)
            } catch (e: Exception) {
                val error = EngineErrors.from(e)
                result.error(error.code, error.message, null)
            }
        }
    }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    private companion object {
        const val CHANNEL = "app/updater"
        const val APK_MIME = "application/vnd.android.package-archive"
    }
}
