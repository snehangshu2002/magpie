package com.snehangshu.magpie.updater

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.snehangshu.magpie.ActivityHost
import com.snehangshu.magpie.engine.EngineErrors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `app/updater`: the installed version and ABIs, so Dart can tell whether a
 * GitHub release is newer and which APK fits; and opens its download link.
 */
class UpdaterBridge(
    private val context: Context,
    private val host: ActivityHost,
) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
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

            else -> result.notImplemented()
        }
    }

    private companion object {
        const val CHANNEL = "app/updater"
    }
}
