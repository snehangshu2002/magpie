package com.snehangshu.media_downloader

import com.snehangshu.media_downloader.engine.YtDlpBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var engineBridge: YtDlpBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineBridge = YtDlpBridge(applicationContext).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        engineBridge?.detach()
        engineBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
