package dev.portable.album_picker

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.*
import android.net.Uri
import android.os.*
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import java.io.*
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

class AlbumPickerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.RequestPermissionsResultListener, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(4)
    private val exportQueue = Executors.newSingleThreadExecutor()
    private val jobs = ConcurrentHashMap<String, AtomicBoolean>()
    private val leases = ConcurrentHashMap<String, File>()
    private var observer: ContentObserver? = null
    private var sink: EventChannel.EventSink? = null
    private val thumbSignals = ConcurrentHashMap<String, MutableSet<CancellationSignal>>()
    private fun root() = File(context.cacheDir, "portable_album_exports").apply { mkdirs() }

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "dev.portable.album_picker")
        channel.setMethodCallHandler(this)
        events = EventChannel(b.binaryMessenger, "dev.portable.album_picker/changes")
        events.setStreamHandler(this)
        io.execute { root().listFiles()?.forEach { f ->
            if (f.isDirectory && System.currentTimeMillis() - f.lastModified() > 86400000L &&
                !jobs.containsKey(f.name) && !leases.containsKey(f.name)) deleteOwned(f)
        } }
    }
    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        onCancel(null); jobs.values.forEach { it.set(true) }
        channel.setMethodCallHandler(null); events.setStreamHandler(null)
        io.shutdown(); exportQueue.shutdown()
    }
    override fun onAttachedToActivity(b: ActivityPluginBinding) { binding = b; activity = b.activity; b.addRequestPermissionsResultListener(this) }
    override fun onDetachedFromActivity() { binding?.removeRequestPermissionsResultListener(this); binding = null; activity = null
        permissionResult?.error("unavailable", "Permission activity unavailable", null); permissionResult = null }
    override fun onDetachedFromActivityForConfigChanges() { binding?.removeRequestPermissionsResultListener(this); binding = null; activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)
    private fun allowed(p: String) = context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    private fun permission(): String {
        val read = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        if (allowed(read)) return "full"
        if (Build.VERSION.SDK_INT >= 34 && allowed(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)) return "limited"
        val asked = context.getSharedPreferences("portable_album_permission", Context.MODE_PRIVATE).getBoolean("asked", false)
        return if (!asked) "unknown" else if (activity?.shouldShowRequestPermissionRationale(read) == true) "denied" else "blocked"
    }
    private fun request(result: MethodChannel.Result) {
        val a = activity ?: return result.error("unavailable", "No permission activity", null)
        if (permissionResult != null) return result.error("busy", "Permission request active", null)
        permissionResult = result
        val permissions = when {
            Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        context.getSharedPreferences("portable_album_permission", Context.MODE_PRIVATE).edit().putBoolean("asked", true).apply()
        a.requestPermissions(permissions, 4841)
    }
    override fun onRequestPermissionsResult(code: Int, p: Array<out String>, grants: IntArray): Boolean {
        if (code != 4841) return false
        permissionResult?.success(permission()); permissionResult = null; return true
    }
    private fun requireRead() { if (permission() !in listOf("full", "limited")) throw ExportFailure("permissionDenied") }
    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
        this.sink = sink
        observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { sink.success(null) } }
        context.contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer!!)
    }
    override fun onCancel(args: Any?) { observer?.let { context.contentResolver.unregisterContentObserver(it) }; observer = null; sink = null }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permission" -> result.success(permission())
            "request", "manage" -> request(result)
            "settings" -> try { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null)
            } catch (_: Exception) { result.error("unavailable", "Settings unavailable", null) }
            "snapshot" -> work(result) { snapshot() }
            "thumbnail" -> work(result) { thumbnail(call.argument<String>("id")!!, call.argument<Int>("size")!!, call.argument<String>("session")!!) }
            "clearThumbnails" -> { thumbSignals.remove(call.argument<String>("session"))?.toList()?.forEach { it.cancel() }; result.success(null) }
            "cancel" -> { jobs[call.argument<String>("token")]?.set(true); result.success(null) }
            "release" -> work(result) {
                val token = call.argument<String>("token")!!
                leases[token]?.let { if (!deleteOwned(it)) throw ExportFailure("cleanupFailed"); leases.remove(token) }; null
            }
            "export" -> {
                val token = call.argument<String>("token")!!
                if (!token.matches(Regex("[A-Za-z0-9_]+"))) return result.error("invalidRequest", "Invalid token", null)
                synchronized(jobs) {
                    if (jobs.isNotEmpty()) return result.error("exportUnavailable", "Export still active", null)
                    jobs[token] = AtomicBoolean(false)
                }
                exportQueue.execute {
                    var value: Map<String, Any>? = null
                    var failure: Throwable? = null
                    try { value = export(call, jobs[token]!!) }
                    catch (e: Throwable) { deleteOwned(root().resolve(token)); failure = e }
                    finally { jobs.remove(token) }
                    val error = failure
                    if (error != null) fail(result, error) else main.post { result.success(value) }
                }
            }
            else -> result.notImplemented()
        }
    }
    private fun work(result: MethodChannel.Result, block: () -> Any?) {
        io.execute { try { val value = block(); main.post { result.success(value) } } catch (e: Throwable) { fail(result, e) } }
    }
    // Only direct children of our private directory; never traverse symlinks.
    private fun deleteOwned(dir: File): Boolean {
        if (dir.parentFile?.absolutePath != root().absolutePath) return false
        fun remove(file: File): Boolean {
            val stat = try { Os.lstat(file.path) } catch (e: ErrnoException) { return e.errno == OsConstants.ENOENT }
            if (OsConstants.S_ISLNK(stat.st_mode)) return false
            if (OsConstants.S_ISDIR(stat.st_mode)) {
                val children = file.listFiles() ?: return false
                if (!children.all { remove(it) }) return false
            }
            return file.delete()
        }
        return remove(dir)
    }
    private fun fail(result: MethodChannel.Result, error: Throwable) {
        val noSpace = generateSequence(error) { it.cause }.any { it is ErrnoException && it.errno == OsConstants.ENOSPC }
        val code = if (noSpace) "insufficientSpace" else when (error) { is ExportFailure -> error.code; is SecurityException -> "permissionDenied"; is FileNotFoundException -> "resourceChanged"; else -> "readFailed" }
        main.post { result.error(code, "Photo operation failed", null) }
    }
    private fun snapshot(): Map<String, Any> {
        requireRead()
        val assets = mutableListOf<Map<String, Any>>()
        val groups = linkedMapOf<String, Map<String, Any>>()
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = mutableListOf("_id", "bucket_id", "bucket_display_name", "datetaken", "date_added", "date_modified", "width", "height", "_size")
        if (Build.VERSION.SDK_INT >= 29) projection.add("volume_name")
        if (Build.VERSION.SDK_INT >= 30) projection.add("generation_modified")
        val selection = if (Build.VERSION.SDK_INT >= 30) "is_pending=0 AND is_trashed=0" else if (Build.VERSION.SDK_INT >= 29) "is_pending=0" else null
        context.contentResolver.query(uri, projection.toTypedArray(), selection, null, null)?.use { c ->
            fun number(name: String) = c.getLong(c.getColumnIndexOrThrow(name))
            fun string(name: String) = c.getString(c.getColumnIndexOrThrow(name)) ?: ""
            while (c.moveToNext()) {
                val volume = if (Build.VERSION.SDK_INT >= 29) string("volume_name") else "external"
                val base = if (Build.VERSION.SDK_INT >= 29) MediaStore.Images.Media.getContentUri(volume) else uri
                val id = ContentUris.withAppendedId(base, number("_id")).toString()
                val group = "$volume:${string("bucket_id")}"
                groups[group] = mapOf("id" to group, "name" to string("bucket_display_name").ifEmpty { "未命名相册" }, "detail" to volume)
                val time = number("datetaken").takeIf { it > 0 } ?: (number("date_added").takeIf { it > 0 } ?: number("date_modified")) * 1000
                assets.add(mapOf("id" to id, "albums" to listOf(group), "time" to time,
                    "revision" to "${number("date_modified")}:${number("_size")}:${if (Build.VERSION.SDK_INT >= 30) number("generation_modified") else 0}", "width" to number("width"), "height" to number("height")))
            }
        } ?: throw ExportFailure("readFailed")
        return mapOf("assets" to assets, "groups" to groups.values.toList())
    }
    private fun imageUri(id: String): Uri {
        val uri = Uri.parse(id)
        if (uri.scheme != "content" || uri.authority != "media" || !uri.path.orEmpty().contains("/images/media/")) throw ExportFailure("invalidRequest")
        return uri
    }
    private fun thumbnail(id: String, size: Int, session: String): ByteArray? {
        requireRead()
        val uri = imageUri(id)
        val signal = CancellationSignal()
        val signals = thumbSignals.computeIfAbsent(session) { ConcurrentHashMap.newKeySet() }
        signals.add(signal)
        var bitmap: Bitmap? = null
        try {
            bitmap = if (Build.VERSION.SDK_INT >= 29) context.contentResolver.loadThumbnail(uri, Size(size, size), signal)
            else MediaStore.Images.Thumbnails.getThumbnail(context.contentResolver, ContentUris.parseId(uri), MediaStore.Images.Thumbnails.MINI_KIND, null)
            if (signal.isCanceled || bitmap == null) return null
            val scaled = android.media.ThumbnailUtils.extractThumbnail(bitmap, size, size)
            try { return ByteArrayOutputStream().use { out -> scaled.compress(Bitmap.CompressFormat.JPEG, 85, out); out.toByteArray() } }
            finally { if (scaled !== bitmap) scaled.recycle() }
        } finally { bitmap?.recycle(); signals.remove(signal) }
    }
    private fun export(call: MethodCall, cancelled: AtomicBoolean): Map<String, Any> {
        requireRead()
        val id = call.argument<String>("id")!!
        val token = call.argument<String>("token")!!
        val uri = imageUri(id)
        val inputLimit = call.argument<Number>("inputBytes")!!.toLong()
        val outputLimit = call.argument<Number>("outputBytes")!!.toLong()
        val dimension = call.argument<Int>("maxDimension")!!
        val pixels = call.argument<Number>("maxPixels")!!.toLong()
        val deadline = SystemClock.elapsedRealtime() + call.argument<Number>("timeoutMs")!!.toLong()
        fun check() { if (cancelled.get()) throw ExportFailure("cancelled"); if (SystemClock.elapsedRealtime() >= deadline) throw ExportFailure("timeout") }
        fun bounds(w: Int, h: Int) { if (w <= 0 || h <= 0) throw ExportFailure("unsupportedFormat"); if (w > dimension || h > dimension || w.toLong() * h > pixels) throw ExportFailure("budgetExceeded") }
        fun revision(): String {
            requireRead()
            val columns = mutableListOf("date_modified", "_size", "width", "height")
            if (Build.VERSION.SDK_INT >= 30) columns.add("generation_modified")
            context.contentResolver.query(uri, columns.toTypedArray(), null, null, null)?.use { c ->
                if (!c.moveToFirst()) throw ExportFailure("resourceChanged")
                if (c.getLong(1) > inputLimit) throw ExportFailure("budgetExceeded")
                if (c.getInt(2) > 0 && c.getInt(3) > 0) bounds(c.getInt(2), c.getInt(3))
                return "${c.getLong(0)}:${c.getLong(1)}:${if (Build.VERSION.SDK_INT >= 30) c.getLong(4) else 0}"
            }
            throw ExportFailure("resourceChanged")
        }
        if (revision() != call.argument<String>("revision")) throw ExportFailure("resourceChanged")
        check()
        val dir = root().resolve(token).apply { if (!mkdir()) throw ExportFailure("writeFailed") }
        if (StatFs(dir.path).availableBytes < inputLimit + outputLimit + 8 * 1024 * 1024) throw ExportFailure("insufficientSpace")
        val source = dir.resolve("input.partial")
        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(source).use { output ->
                val buffer = ByteArray(64 * 1024); var total = 0L
                while (true) { check(); val n = input.read(buffer); if (n < 0) break
                    total += n; if (total > inputLimit) throw ExportFailure("budgetExceeded"); output.write(buffer, 0, n) }
            }
        } ?: throw ExportFailure("readFailed")
        check()
        val header = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, header); bounds(header.outWidth, header.outHeight)
        if (header.outMimeType !in listOf("image/jpeg", "image/png", "image/gif", "image/heic", "image/heif")) throw ExportFailure("unsupportedFormat")
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888
            if (Build.VERSION.SDK_INT >= 26) inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB) }
        val decoded = BitmapFactory.decodeFile(source.path, options) ?: throw ExportFailure("unsupportedFormat")
        var normalized: Bitmap? = null
        try {
            check()
            val orientation = try { ExifInterface(source).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) } catch (_: IOException) { 1 }
            val matrix = Matrix()
            when (orientation) {
                2 -> matrix.setScale(-1f, 1f)
                3 -> matrix.setRotate(180f)
                4 -> { matrix.setRotate(180f); matrix.postScale(-1f, 1f) }
                5 -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                6 -> matrix.setRotate(90f)
                7 -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                8 -> matrix.setRotate(-90f)
            }
            val frame = RectF(0f, 0f, decoded.width.toFloat(), decoded.height.toFloat())
            matrix.mapRect(frame)
            matrix.postTranslate(-frame.left, -frame.top)
            val width = frame.width().toInt(); val height = frame.height().toInt()
            bounds(width, height)
            normalized = if (Build.VERSION.SDK_INT >= 26) Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888, true, ColorSpace.get(ColorSpace.Named.SRGB))
                else Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            Canvas(normalized).drawBitmap(decoded, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
            check()
            val partial = dir.resolve("output.partial")
            FileOutputStream(partial).use { file ->
                val out = BoundedOutputStream(file, outputLimit, ::check)
                val encoded = normalized.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.failure?.let { throw it }
                if (!encoded) throw ExportFailure("writeFailed")
                file.fd.sync()
            }
            check()
            if (revision() != call.argument<String>("revision")) throw ExportFailure("resourceChanged")
            val verified = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(partial.path, verified)
            if (verified.outMimeType != "image/png" || verified.outWidth != normalized.width || verified.outHeight != normalized.height) throw ExportFailure("writeFailed")
            val final = dir.resolve("image.png")
            if (!partial.renameTo(final)) throw ExportFailure("writeFailed")
            source.delete(); check(); leases[token] = dir
            return mapOf("path" to final.path, "bytes" to final.length(), "width" to normalized.width, "height" to normalized.height,
                "kind" to if (header.outMimeType == "image/gif") "gifFirstFrame" else "photo")
        } finally {
            normalized?.recycle(); decoded.recycle()
        }
    }
}
