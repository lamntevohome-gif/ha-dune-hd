package vn.evohome.evoknx

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives a project file (.evoknx) that is shared to the App ("Chia sẻ → EvoKNX")
 * or opened with it. The content is copied into the cache folder and its path is
 * given to Dart through the "evoknx/share" channel.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "evoknx/share")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "initialFile") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        handle(intent, false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent, true)
    }

    private fun handle(intent: Intent?, running: Boolean) {
        val uri = uriOf(intent) ?: return
        val path = copy(uri) ?: return
        if (running) {
            channel?.invokeMethod("sharedFile", path)
        } else {
            pending = path
        }
    }

    @Suppress("DEPRECATION")
    private fun uriOf(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
    }

    private fun copy(uri: Uri): String? {
        try {
            val out = File(cacheDir, "shared_" + System.currentTimeMillis() + ".evoknx")
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
            // A project is a few hundred KB; refuse anything much larger.
            if (out.length() > 30L * 1024 * 1024) {
                out.delete()
                return null
            }
            return out.absolutePath
        } catch (e: Exception) {
            return null
        }
    }
}
