package ua.svitlo.app

import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "svitlo/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "version" to info.versionName,
                                "abis" to Build.SUPPORTED_ABIS.toList(),
                                "cacheDir" to cacheDir.absolutePath,
                            )
                        )
                    }
                    "installApk" -> {
                        val file = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
