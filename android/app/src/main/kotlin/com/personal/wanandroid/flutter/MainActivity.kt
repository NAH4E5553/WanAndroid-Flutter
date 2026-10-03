package com.personal.wanandroid.flutter

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * 最小原生平台通道：承载头像「保存到相册」与 EXIF 像素归一；Android 端
 * excludeFromBackup 为 no-op，备份已由 manifest allowBackup=false 全局关闭。
 * 拍照与选图仍走 image_picker 的系统页，本类不涉及 CAMERA 权限。
 *
 * API 24–28 的降级保存分两段异步：先申请 WRITE_EXTERNAL_STORAGE，授权后写
 * 公开目录文件并触发媒体扫描，扫描回调（主线程投递）完成后才回传结果——
 * 扫描成功即图片已在图库可见，不误报成功；两段共用同一 pending 槽。
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Match the system splash's full-window center in Flutter. The
            // Flutter overlay owns the only fade; a system fade would expose
            // and then re-cover the matching first frame.
            window.setDecorFitsSystemWindows(false)
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        super.onCreate(savedInstanceState)
    }

    private val channelName = "dev.flutter.local.avatar_gallery"
    private val imageChannelName = "dev.flutter.local.avatar_image"
    private val writePermissionRequestCode = 4711

    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveFileName: String? = null
    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveTargetPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePng" -> handleSavePng(call, result)
                "excludeFromBackup" -> result.success("success")
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            imageChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "normalizeToPng" -> result.success(normalizeToPng(call))
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSavePng(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")
        if (fileName == null || bytes == null) {
            result.success("failure")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+：MediaStore 贡献式写入，无需存储权限。
            result.success(saveViaMediaStoreQ(fileName, bytes))
            return
        }
        val permission = Manifest.permission.WRITE_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            // 已授权：直接进入写文件 + 媒体扫描的异步段。
            beginLegacySave(fileName, bytes, result)
            return
        }
        if (pendingSaveResult != null) {
            // 已有在途保存：拒绝并发第二次（Dart 层另有单飞，防御性兜底）。
            result.success("failure")
            return
        }
        pendingSaveResult = result
        pendingSaveFileName = fileName
        pendingSaveBytes = bytes
        ActivityCompat.requestPermissions(
            this,
            arrayOf(permission),
            writePermissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != writePermissionRequestCode) {
            return
        }
        val result = pendingSaveResult ?: return
        val fileName = pendingSaveFileName
        val bytes = pendingSaveBytes
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        when {
            granted && fileName != null && bytes != null -> {
                // pending 槽被 beginLegacySave 复用为扫描等待段。
                beginLegacySave(fileName, bytes, result)
            }
            ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) -> finishPendingSave("permissionDenied")
            else -> finishPendingSave("permissionPermanentlyDenied")
        }
    }

    private fun beginLegacySave(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        try {
            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "WanAndroidFlutter",
            )
            if (!directory.exists() && !directory.mkdirs()) {
                finishLegacySave(result, "failure")
                return
            }
            val target = File(directory, fileName)
            FileOutputStream(target).use { stream -> stream.write(bytes) }
            pendingSaveResult = result
            pendingSaveFileName = fileName
            pendingSaveBytes = bytes
            pendingSaveTargetPath = target.absolutePath
            MediaScannerConnection.scanFile(
                this,
                arrayOf(target.absolutePath),
                arrayOf("image/png"),
            ) { _, uri ->
                // 主线程回调：扫描成功即图库可见；失败则删除文件不误报成功。
                if (uri == null) {
                    File(pendingSaveTargetPath ?: target.absolutePath).delete()
                }
                finishPendingSave(if (uri != null) "success" else "failure")
            }
        } catch (error: Exception) {
            finishLegacySave(result, mapFailure(error))
        }
    }

    private fun finishLegacySave(result: MethodChannel.Result, code: String) {
        if (pendingSaveResult === result) {
            finishPendingSave(code)
            return
        }
        pendingSaveResult = null
        pendingSaveFileName = null
        pendingSaveBytes = null
        pendingSaveTargetPath = null
        result.success(code)
    }

    private fun finishPendingSave(code: String) {
        val result = pendingSaveResult ?: return
        pendingSaveResult = null
        pendingSaveFileName = null
        pendingSaveBytes = null
        pendingSaveTargetPath = null
        result.success(code)
    }

    private fun saveViaMediaStoreQ(fileName: String, bytes: ByteArray): String {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/WanAndroidFlutter",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return "failure"
        try {
            val stream = resolver.openOutputStream(uri)
            if (stream == null) {
                resolver.delete(uri, null, null)
                return "failure"
            }
            stream.use { output -> output.write(bytes) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            if (resolver.update(uri, values, null, null) != 1) {
                resolver.delete(uri, null, null)
                return "failure"
            }
            return "success"
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            return mapFailure(error)
        }
    }

    private fun normalizeToPng(call: MethodCall): String {
        val sourcePath = call.argument<String>("sourcePath") ?: return "failure"
        val destinationPath = call.argument<String>("destinationPath") ?: return "failure"
        val maxDimension = call.argument<Int>("maxDimension") ?: return "failure"
        val maxPixelCount = call.argument<Int>("maxPixelCount") ?: return "failure"
        val maxFileBytes = call.argument<Int>("maxFileBytes") ?: return "failure"
        val source = File(sourcePath)
        val destination = File(destinationPath)
        var decoded: Bitmap? = null
        var normalized: Bitmap? = null
        var temporary: File? = null
        try {
            if (!source.isFile || source.length() <= 0 || source.length() > maxFileBytes) {
                return "rejected"
            }
            val allowedRoots = listOf(filesDir, cacheDir, noBackupFilesDir)
            val destinationCanonical = destination.canonicalFile
            val allowed = allowedRoots.any { root ->
                destinationCanonical.path.startsWith(root.canonicalPath + File.separator)
            }
            if (!allowed) {
                return "failure"
            }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(source.path, bounds)
            val width = bounds.outWidth
            val height = bounds.outHeight
            if (
                width <= 0 || height <= 0 || width > maxDimension || height > maxDimension ||
                width.toLong() * height.toLong() > maxPixelCount.toLong()
            ) {
                return "rejected"
            }
            decoded = BitmapFactory.decodeFile(source.path)
                ?: return "failure"
            val exif = ExifInterface(source.path)
            val matrix = Matrix()
            if (exif.isFlipped) {
                matrix.postScale(-1f, 1f)
            }
            if (exif.rotationDegrees != 0) {
                matrix.postRotate(exif.rotationDegrees.toFloat())
            }
            normalized = if (matrix.isIdentity) {
                decoded
            } else {
                Bitmap.createBitmap(
                    decoded,
                    0,
                    0,
                    decoded.width,
                    decoded.height,
                    matrix,
                    true,
                )
            }
            destinationCanonical.parentFile?.mkdirs()
            temporary = File(destinationCanonical.path + ".normalizing")
            FileOutputStream(temporary).use { output ->
                if (!normalized.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    throw IllegalStateException("png encode failed")
                }
                output.fd.sync()
            }
            if (destinationCanonical.exists() && !destinationCanonical.delete()) {
                throw IllegalStateException("destination replace failed")
            }
            if (!temporary.renameTo(destinationCanonical)) {
                throw IllegalStateException("atomic rename failed")
            }
            temporary = null
            return "success"
        } catch (_: Exception) {
            return "failure"
        } finally {
            temporary?.delete()
            if (normalized != null && normalized !== decoded) {
                normalized.recycle()
            }
            decoded?.recycle()
        }
    }

    private fun mapFailure(error: Exception): String {
        val message = error.message ?: return "failure"
        val space = message.contains("space", ignoreCase = true)
        val full = message.contains("full", ignoreCase = true)
        return if (space || (message.contains("storage", ignoreCase = true) && full)) {
            "insufficientSpace"
        } else {
            "failure"
        }
    }
}
