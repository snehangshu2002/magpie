package com.snehangshu.magpie

import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import com.snehangshu.magpie.engine.YtDlpBridge
import com.snehangshu.magpie.storage.StorageBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity(), ActivityHost {
    private var engineBridge: YtDlpBridge? = null
    private var storageBridge: StorageBridge? = null

    // Permission prompts and system confirmations waiting for their result, by request code.
    private val pendingPermissions = mutableMapOf<Int, CompletableDeferred<Unit>>()
    private val pendingConfirmations = mutableMapOf<Int, CompletableDeferred<Boolean>>()
    private var nextRequestCode = 1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        engineBridge = YtDlpBridge(applicationContext, this).also { it.attach(messenger) }
        storageBridge = StorageBridge(applicationContext, this).also { it.attach(messenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        engineBridge?.detach()
        engineBridge = null
        storageBridge?.detach()
        storageBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // Nobody will answer these any more; let the callers carry on.
        pendingPermissions.values.forEach { it.complete(Unit) }
        pendingPermissions.clear()
        pendingConfirmations.values.forEach { it.complete(false) }
        pendingConfirmations.clear()
        super.onDestroy()
    }

    override suspend fun requestPermissions(permissions: List<String>) {
        val answered = withContext(Dispatchers.Main) {
            val missing = permissions.filter {
                checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing.isEmpty() || isFinishing) return@withContext null
            val code = nextRequestCode++
            CompletableDeferred<Unit>().also {
                pendingPermissions[code] = it
                requestPermissions(missing.toTypedArray(), code)
            }
        }
        answered?.await()
    }

    override suspend fun confirm(request: IntentSender): Boolean {
        val answered = withContext(Dispatchers.Main) {
            if (isFinishing) return@withContext null
            val code = nextRequestCode++
            CompletableDeferred<Boolean>().also {
                pendingConfirmations[code] = it
                startIntentSenderForResult(request, code, null, 0, 0, 0)
            }
        }
        return answered?.await() ?: false
    }

    override fun launch(intent: Intent) = startActivity(intent)

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        pendingPermissions.remove(requestCode)?.complete(Unit)
    }

    // FlutterActivity is not a ComponentActivity, so there is no ActivityResult API.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        pendingConfirmations.remove(requestCode)?.complete(resultCode == RESULT_OK)
    }
}
