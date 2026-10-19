package com.snehangshu.magpie.engine

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * `app/engine/progress` payloads from [DownloadService], forwarded to Dart
 * by [YtDlpBridge] while the UI is attached.
 */
internal object DownloadEvents {
    private val flow = MutableSharedFlow<Map<String, Any?>>(
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    val events: SharedFlow<Map<String, Any?>> = flow

    fun emit(event: Map<String, Any?>) {
        flow.tryEmit(event)
    }
}
