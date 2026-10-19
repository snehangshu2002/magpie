package com.snehangshu.magpie.share

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Sends text shared from other apps to Dart on `app/share`. A share that
 * arrives before Dart listens (cold start, or right after the app opened) is
 * kept and sent when it does, so it is never dropped.
 */
class ShareBridge : EventChannel.StreamHandler {
    private var channel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var pending: String? = null

    fun attach(messenger: BinaryMessenger) {
        channel = EventChannel(messenger, CHANNEL).also { it.setStreamHandler(this) }
    }

    fun detach() {
        channel?.setStreamHandler(null)
        channel = null
        sink = null
    }

    /** Takes the text of a `SEND` intent; ignores anything else. */
    fun handle(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        // Reopening from Recents replays the intent that first opened the app.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        sink?.success(text) ?: run { pending = text }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pending?.let(events::success)
        pending = null
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private companion object {
        const val CHANNEL = "app/share"
    }
}
