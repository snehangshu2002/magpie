package com.snehangshu.magpie

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `app/appearance`: tells Android the theme chosen in Settings, so the
 * launch screen (drawn before Flutter starts) uses it too. Android 12+
 * remembers it per app; older versions keep following the phone.
 */
class AppearanceBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setNightMode") return result.notImplemented()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(UiModeManager::class.java).setApplicationNightMode(
                when (call.argument<String>("mode")) {
                    "light" -> UiModeManager.MODE_NIGHT_NO
                    "dark" -> UiModeManager.MODE_NIGHT_YES
                    else -> UiModeManager.MODE_NIGHT_AUTO
                },
            )
        }
        result.success(null)
    }

    private companion object {
        const val CHANNEL = "app/appearance"
    }
}
