package dev.portable.album_picker_example

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.os.Debug
import android.os.SystemClock
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Debug example only. Creates and queries ONLY recorded synthetic resources.
 * The independent baseline query reads the public media provider with a
 * separately written projection/selection; it never reuses plugin code and
 * only returns opaque rows to the on-device test process.
 */
class ControlledAlbumFixtures(context: Context, engine: FlutterEngine) {
    private val app = context.applicationContext
    private val resolver = app.contentResolver
    private val prefs = app.getSharedPreferences("controlled_album_fixtures", Context.MODE_PRIVATE)
    private fun owned() = prefs.getStringSet("uris", emptySet())!!.toMutableSet()
    private fun subset(key: String) = prefs.getStringSet(key, emptySet())!!.toMutableSet()

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.portable.album_fixture").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "seed" -> { require(Build.VERSION.SDK_INT >= 30); cleanup(); seed(); result.success(null) }
                    "describe" -> result.success(describe())
                    "deleteFirst" -> { val uri = owned().sortedBy { ContentUris.parseId(Uri.parse(it)) }.firstOrNull(); if (uri != null) remove(uri); result.success(null) }
                    "cleanup" -> { cleanup(); result.success(owned().size) }
                    "sweepOrphans" -> result.success(sweepOrphans())
                    "sweepProtectionProbe" -> result.success(sweepProtectionProbe())
                    "exifProbe" -> result.success(exifProbe(call.argument<String>("uri")!!))
                    "probeTargets" -> result.success(prefs.all.keys.filter { it.startsWith("expectedTaken_") }.associate {
                        it.removePrefix("expectedTaken_") to (prefs.getString(it, "") ?: "")
                    })
                    "phase" -> { File(app.filesDir, "album_test_phase.txt").writeText(call.argument<String>("value")!!); result.success(null) }
                    "baseline" -> result.success(baseline())
                    "seedIntegrity" -> result.success(seedIntegrity())
                    "seedPerfSamples" -> result.success(seedPerfSamples())
                    "describeIntegrity" -> result.success(describeIntegrity())
                    "integrityMove" -> result.success(integrityMove(call.argument<String>("from")!!, call.argument<String>("to")!!))
                    "dynamicInsert" -> result.success(dynamicInsert(call.argument<String>("path")!!, call.argument<Int>("count")!!, call.argument<Boolean>("pendingFirst") ?: true))
                    "deleteUri" -> { deleteRecorded(call.argument<String>("uri")!!, "integrity"); result.success(null) }
                    "generateDataset" -> result.success(generateDataset(call.argument<Int>("target")!!))
                    "datasetStats" -> result.success(datasetStats())
                    "meminfo" -> result.success(meminfo())
                    "exportCacheBytes" -> result.success(exportCacheBytes())
                    "report" -> { File(app.filesDir, "album_report.json").writeText(call.argument<String>("text")!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error(
                    "fixtureFailed",
                    "Controlled fixture operation failed: ${e.javaClass.simpleName}: ${e.message}",
                    null,
                )
            }
        }
    }

    private fun seed() {
        val run = UUID.randomUUID().toString().take(8)
        repeat(8) { index ->
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "controlled_${run}_$index.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/AlbumPickerCheck_${run}_${if (index < 4) "A" else "B"}")
                put(MediaStore.Images.Media.IS_PENDING, 1)
                put(MediaStore.Images.Media.WIDTH, 96); put(MediaStore.Images.Media.HEIGHT, 64)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("insert")
            prefs.edit().putStringSet("uris", owned().apply { add(uri.toString()) }).commit()
            val bitmap = Bitmap.createBitmap(96, 64, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.rgb(30 + index * 20, 80, 180))
            try { resolver.openOutputStream(uri)!!.use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
            finally { bitmap.recycle() }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
        }
    }

    private fun remove(value: String) {
        check(value in owned())
        val uri = Uri.parse(value)
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) { check(c.getString(0) == app.packageName); resolver.delete(uri, null, null) }
        }
        prefs.edit().putStringSet("uris", owned().apply { remove(value) }).commit()
    }

    private fun deleteRecorded(value: String, setKey: String?) {
        val uri = Uri.parse(value)
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && c.getString(0) == app.packageName) { resolver.delete(uri, null, null) }
        }
        val uris = owned(); uris.remove(value)
        val edit = prefs.edit().putStringSet("uris", uris)
        if (setKey != null) { val s = subset(setKey); s.remove(value); edit.putStringSet(setKey, s) }
        edit.commit()
    }

    /** Delete every recorded resource with owner check, then clear bookkeeping once.
     *  Rows that no longer exist count as cleaned (idempotent re-runs).
     *  On failure the RAW URIs (never annotated strings) are written back so a
     *  later retry still queries valid rows; failure notes are kept separate. */
    private fun cleanup() {
        val all = owned()
        val failedUris = mutableListOf<String>()
        val failedNotes = mutableListOf<String>()
        for (value in all) {
            val uri = Uri.parse(value)
            var gone = false
            val note: String
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use { c ->
                when {
                    !c.moveToFirst() -> gone = true
                    c.getString(0) == app.packageName -> gone = resolver.delete(uri, null, null) == 1
                    else -> {}
                }
            } ?: run { gone = true }
            if (!gone) {
                failedUris.add(value)
                failedNotes.add("$value (owner mismatch or delete refused)")
            }
        }
        if (failedUris.isNotEmpty()) {
            val keep = failedUris.toSet()
            val integrityKeep = subset("integrity").filter { it in keep }.toSet()
            val datasetKeep = subset("dataset").filter { it in keep }.toSet()
            prefs.edit()
                .putStringSet("uris", keep)
                .putStringSet("integrity", integrityKeep)
                .putStringSet("dataset", datasetKeep)
                .commit()
            error("cleanup left ${failedUris.size} recorded resources, notes: ${failedNotes.take(3)}")
        }
        prefs.edit().clear().commit()
    }

    /**
     * Sweep rows that carry our unique fixture name prefixes but are missing
     * from the recorded bookkeeping (crash between insert and prefs commit,
     * or a previous uninstalled run). Every candidate row is owner-verified
     * before deletion; nothing else is touched.
     */
    private fun sweepOrphans(): Int {
        val projection = arrayOf("_id", "volume_name", "owner_package_name")
        val selection = "_display_name LIKE 'integ\\_%' ESCAPE '\\' OR _display_name LIKE 'perf\\_%' ESCAPE '\\' OR _display_name LIKE 'controlled\\_%' ESCAPE '\\'"
        // Rows present in the recorded bookkeeping (dataset/integrity subsets)
        // are owned by that flow's own cleanup; sweeping them here would break
        // cumulative dataset runs. Matching uses the numeric media id because
        // the recorded insert URI and a freshly built canonical URI may spell
        // the volume differently ("external" vs "external_primary") while
        // pointing at the same row; the owner check below still applies.
        val recordedIds = owned().mapNotNull { value ->
            runCatching { ContentUris.parseId(Uri.parse(value)) }.getOrNull()
        }.toSet()
        var removed = 0
        resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(2) != app.packageName) continue
                val rowId = c.getLong(0)
                if (rowId in recordedIds) continue
                val uri = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(c.getString(1)), rowId)
                if (resolver.delete(uri, null, null) == 1) removed++
            }
        }
        return removed
    }

    private fun describe(): List<Map<String, Any>> {
        return owned().sortedBy { ContentUris.parseId(Uri.parse(it)) }.mapNotNull { value ->
            // Exact recorded URI query, never enumerate the personal library.
            resolver.query(Uri.parse(value), arrayOf("_id", "volume_name", "bucket_id", "width", "height", "date_modified", "_size", "generation_modified", "bucket_display_name"), null, null, null)?.use { c ->
                if (!c.moveToFirst()) return@use null
                val id = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(c.getString(1)), c.getLong(0)).toString()
                mapOf("id" to id, "group" to "${c.getString(1)}:${c.getString(2)}", "name" to c.getString(8),
                    "width" to c.getInt(3), "height" to c.getInt(4), "revision" to "${c.getLong(5)}:${c.getLong(6)}:${c.getLong(7)}")
            }
        }
    }

    /**
     * Independent integrity baseline over the public media provider, written
     * from the component's documented support scope (normal images, visible,
     * not pending/trashed, all mounted external volumes). Separate code path
     * from the plugin gateway; rows stay inside the test process.
     */
    private fun baseline(): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        val projection = arrayOf("_id", "volume_name", "bucket_id", "datetaken", "date_added", "date_modified", "width", "height", "mime_type")
        val selection = if (Build.VERSION.SDK_INT >= 30) "is_pending=0 AND is_trashed=0" else if (Build.VERSION.SDK_INT >= 29) "is_pending=0" else null
        resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null)?.use { c ->
            while (c.moveToNext()) {
                val volume = c.getString(c.getColumnIndexOrThrow("volume_name"))
                val id = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(volume), c.getLong(c.getColumnIndexOrThrow("_id"))).toString()
                rows.add(mapOf(
                    "id" to id,
                    "volume" to volume,
                    "bucket" to c.getString(c.getColumnIndexOrThrow("bucket_id")),
                    "datetaken" to c.getLong(c.getColumnIndexOrThrow("datetaken")),
                    "dateAdded" to c.getLong(c.getColumnIndexOrThrow("date_added")),
                    "dateModified" to c.getLong(c.getColumnIndexOrThrow("date_modified")),
                    "width" to c.getInt(c.getColumnIndexOrThrow("width")),
                    "height" to c.getInt(c.getColumnIndexOrThrow("height")),
                    "mime" to (c.getString(c.getColumnIndexOrThrow("mime_type")) ?: ""),
                ))
            }
        } ?: error("baseline query failed")
        return rows
    }

    private fun pendingValues(name: String, path: String, width: Int, height: Int, datetaken: Long, mime: String = "image/jpeg") = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, name)
        put(MediaStore.Images.Media.MIME_TYPE, mime)
        put(MediaStore.Images.Media.RELATIVE_PATH, path)
        put(MediaStore.Images.Media.IS_PENDING, 1)
        if (width > 0) { put(MediaStore.Images.Media.WIDTH, width); put(MediaStore.Images.Media.HEIGHT, height) }
        if (datetaken > 0) put(MediaStore.Images.Media.DATE_TAKEN, datetaken)
    }

    private fun writeBitmap(uri: Uri, width: Int, height: Int, pattern: Int, seed: Int, gif: Boolean = false) {
        if (gif) { resolver.openOutputStream(uri)!!.use { it.write(gifBytes()) }; return }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint()
        when (pattern) {
            0 -> { // flat field plus border, compresses small
                canvas.drawColor(Color.rgb(seed % 256, 90 + seed % 100, 60 + seed % 150))
                paint.color = Color.BLACK; paint.strokeWidth = 12f; paint.style = Paint.Style.STROKE
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            }
            1 -> { // diagonal gradient
                val step = 24
                var y = 0
                while (y < height) {
                    paint.color = Color.rgb((y * 255) / height, (seed * 7 + y) % 256, 255 - (y * 255) / height)
                    canvas.drawRect(0f, y.toFloat(), width.toFloat(), (y + step).toFloat(), paint)
                    y += step
                }
            }
            else -> { // 8px vertical stripes, high entropy for JPEG
                var x = 0
                while (x < width) {
                    paint.color = if ((x / 8) % 2 == 0) Color.rgb(seed % 256, 40, 220 - seed % 100) else Color.WHITE
                    canvas.drawRect(x.toFloat(), 0f, (x + 8).toFloat(), height.toFloat(), paint)
                    x += 8
                }
            }
        }
        try { resolver.openOutputStream(uri)!!.use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it)) } }
        finally { bitmap.recycle() }
    }

    private fun record(uri: Uri, integrity: Boolean) {
        val uris = owned(); uris.add(uri.toString())
        val integritySet = subset("integrity"); if (integrity) integritySet.add(uri.toString())
        prefs.edit().putStringSet("uris", uris).putStringSet("integrity", integritySet).commit()
    }

    private fun insertFixture(values: ContentValues, integrity: Boolean): Uri {
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("insert")
        record(uri, integrity)
        return uri
    }

    private fun finishPending(uri: Uri) =
        resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)

    /**
     * Draw the fixture bitmap and write the JPEG to the row in ONE pass with
     * EXIF DateTimeOriginal already present. The previous double-write flow
     * (bitmap first, EXIF added by rewriting the pending row) lost datetaken
     * on every scanned row, while the single-write rotated fixture kept its
     * EXIF orientation — the rewrite-while-pending is the difference under
     * test, and this helper removes that variable entirely.
     */
    private fun writeJpegWithExif(uri: Uri, width: Int, height: Int, pattern: Int, seed: Int, takenMs: Long) {
        val temp = File.createTempFile("integ_jpeg", ".jpg", app.cacheDir)
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            drawPattern(bitmap, pattern, seed)
            temp.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it)) }
            bitmap.recycle()
            if (takenMs > 0) {
                val exif = androidx.exifinterface.media.ExifInterface(temp.path)
                exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_DATETIME_ORIGINAL, exifText(takenMs))
                exif.saveAttributes()
            }
            resolver.openOutputStream(uri)!!.use { out -> temp.inputStream().use { out.write(it.readBytes()) } }
        } finally { temp.delete() }
    }

    private fun drawPattern(bitmap: Bitmap, pattern: Int, seed: Int) {
        val canvas = Canvas(bitmap)
        val paint = Paint()
        val width = bitmap.width; val height = bitmap.height
        when (pattern) {
            0 -> { // flat field plus border, compresses small
                canvas.drawColor(Color.rgb(seed % 256, 90 + seed % 100, 60 + seed % 150))
                paint.color = Color.BLACK; paint.strokeWidth = 12f; paint.style = Paint.Style.STROKE
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            }
            1 -> { // diagonal gradient
                val step = 24
                var y = 0
                while (y < height) {
                    paint.color = Color.rgb((y * 255) / height, (seed * 7 + y) % 256, 255 - (y * 255) / height)
                    canvas.drawRect(0f, y.toFloat(), width.toFloat(), (y + step).toFloat(), paint)
                    y += step
                }
            }
            else -> { // 8px vertical stripes, high entropy for JPEG
                var x = 0
                while (x < width) {
                    paint.color = if ((x / 8) % 2 == 0) Color.rgb(seed % 256, 40, 220 - seed % 100) else Color.WHITE
                    canvas.drawRect(x.toFloat(), 0f, (x + 8).toFloat(), height.toFloat(), paint)
                    x += 8
                }
            }
        }
    }

    /**
     * Four-point capture chain for one recorded row: the seeded expectation,
     * the EXIF DateTimeOriginal still present in the stored file bytes, the
     * MediaStore column values after publishing, and (Dart-side) the time the
     * component derives. Separates a fixture-pipeline break from scanner
     * behavior; never touches personal media.
     */
    private fun exifProbe(uri: String): Map<String, Any> {
        val expected = prefs.getString("expectedTaken_$uri", null)
        val fileExif = runCatching {
            resolver.openInputStream(Uri.parse(uri))?.use { input ->
                val exif = androidx.exifinterface.media.ExifInterface(input)
                exif.getAttribute(androidx.exifinterface.media.ExifInterface.TAG_DATETIME_ORIGINAL)
            }
        }.getOrNull() ?: ""
        var columnTaken = 0L; var columnAdded = 0L; var columnModified = 0L
        resolver.query(Uri.parse(uri), arrayOf("datetaken", "date_added", "date_modified"), null, null, null)?.use { c ->
            if (c.moveToFirst()) { columnTaken = c.getLong(0); columnAdded = c.getLong(1); columnModified = c.getLong(2) }
        }
        return mapOf(
            "expected" to (expected ?: ""),
            "fileExif" to (fileExif ?: ""),
            "columnTaken" to columnTaken,
            "columnAdded" to columnAdded,
            "columnModified" to columnModified,
        )
    }

    /** Availability / ordering / grouping samples; every row is app-owned and recorded. */
    private fun seedIntegrity(): Map<String, Any> {
        val run = UUID.randomUUID().toString().take(8)
        var inserted = 0
        var rotatedIncluded = false
        val dirs = mutableListOf<String>()
        fun dir(name: String): String { dirs.add(name); return name }

        val dirA = dir("IntegrityG_${run}_A"); val dirB = dir("IntegrityG_${run}_B")
        val base = System.currentTimeMillis() / 1000 * 1000 - 86_400_000L
        repeat(4) { i ->
            val taken = base - i * 60_000L
            val uri = insertFixture(pendingValues("integ_g_${run}_$i.jpg", "Pictures/$dirA", 640, 480, taken), true); inserted++
            if (i == 0) prefs.edit().putString("expectedTaken_$uri", taken.toString()).commit()
            writeJpegWithExif(uri, 640, 480, i % 3, i, taken); finishPending(uri)
        }
        repeat(2) { i ->
            val taken = base - (i + 10) * 60_000L
            val uri = insertFixture(pendingValues("integ_g_${run}_b$i.jpg", "Pictures/$dirB", 480, 640, taken), true); inserted++
            writeJpegWithExif(uri, 480, 640, i, i + 3, taken); finishPending(uri)
        }
        // Same display name in two different directories must stay two groups.
        val sameName = dir("IntegritySameName_$run")
        insertFixture(pendingValues("integ_same_${run}_p.jpg", "Pictures/$sameName", 320, 240, base - 90_000L), true).let { writeJpegWithExif(it, 320, 240, 0, 1, base - 90_000L); finishPending(it) }; inserted++
        insertFixture(pendingValues("integ_same_${run}_d.jpg", "DCIM/$sameName", 320, 240, base - 80_000L), true).let { writeJpegWithExif(it, 320, 240, 1, 2, base - 80_000L); finishPending(it) }; inserted++
        // 100 identical timestamps cross the 80-item page boundary; ties break by ID.
        val tieDir = dir("IntegrityTie_$run")
        val tieTime = base - 120_000L
        repeat(100) { i ->
            val uri = insertFixture(pendingValues("integ_tie_${run}_%03d.jpg".format(Locale.US, i), "Pictures/$tieDir", 160, 120, tieTime), true); inserted++
            if (i == 0) prefs.edit().putString("expectedTaken_$uri", tieTime.toString()).commit()
            writeJpegWithExif(uri, 160, 120, i % 3, i, tieTime); finishPending(uri)
        }
        val edgeDir = dir("IntegrityEdge_$run")
        // The old fixture is inserted LAST with a capture time three hours
        // before every other fixture, so capture time must beat insertion
        // order. Whether that premise holds on this device is decided by the
        // readback gate in the Dart test, never assumed.
        val oldTaken = base - 3 * 3_600_000L
        val oldUri = insertFixture(pendingValues("integ_old_$run.jpg", "Pictures/$edgeDir", 320, 240, oldTaken), true); inserted++
        prefs.edit().putString("expectedTaken_$oldUri", oldTaken.toString()).commit()
        writeJpegWithExif(oldUri, 320, 240, 0, 5, oldTaken); finishPending(oldUri)
        insertFixture(pendingValues("integ_fallback1_$run.jpg", "Pictures/$edgeDir", 320, 240, 0), true).let { writeBitmap(it, 320, 240, 1, 6); finishPending(it) }; inserted++
        insertFixture(pendingValues("integ_fallback2_$run.jpg", "Pictures/$edgeDir", 320, 240, 0), true).let { writeBitmap(it, 320, 240, 2, 7); finishPending(it) }; inserted++

        val specDir = dir("IntegritySpec_$run")
        insertFixture(pendingValues("integ_long_$run.jpg", "Pictures/$specDir", 256, 4096, base - 150_000L), true).let { writeJpegWithExif(it, 256, 4096, 1, 8, base - 150_000L); finishPending(it) }; inserted++
        insertFixture(pendingValues("integ_large_$run.jpg", "Pictures/$specDir", 5120, 3840, base - 160_000L), true).let { writeJpegWithExif(it, 5120, 3840, 1, 9, base - 160_000L); finishPending(it) }; inserted++
        runCatching {
            val uri = insertFixture(pendingValues("integ_rot_$run.jpg", "Pictures/$specDir", 960, 1280, base - 170_000L), true)
            writeRotated(uri, 960, 1280)
            finishPending(uri)
            inserted++; rotatedIncluded = true
        }.onFailure {
            // Leave no pending or broken row behind if EXIF tooling is missing.
            subset("integrity").lastOrNull()?.let { deleteRecorded(it, "integrity") }
        }
        insertFixture(pendingValues("integ_gif_$run.gif", "Pictures/$specDir", 8, 8, base - 180_000L, mime = "image/gif"), true).let {
            writeBitmap(it, 8, 8, 0, 10, gif = true); finishPending(it)
        }; inserted++
        insertFixture(pendingValues("integ_corrupt_$run.png", "Pictures/$specDir", 0, 0, base - 190_000L, mime = "image/png"), true).let { uri ->
            resolver.openOutputStream(uri)!!.use { out ->
                out.write(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
                out.write(ByteArray(4096) { (it * 31 % 251).toByte() })
            }
            finishPending(uri)
        }; inserted++
        return mapOf("inserted" to inserted, "dirs" to dirs, "rotatedIncluded" to rotatedIncluded)
    }

    /** 960x1280 JPEG with EXIF orientation 6. Throws when ExifInterface is unavailable. */
    private fun writeRotated(uri: Uri, width: Int, height: Int) {
        val temp = File.createTempFile("integ_rot", ".jpg", app.cacheDir)
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap); val paint = Paint()
            paint.color = Color.rgb(20, 180, 60); canvas.drawRect(0f, 0f, width / 2f, height.toFloat(), paint)
            paint.color = Color.rgb(240, 200, 30); canvas.drawRect(width / 2f, 0f, width.toFloat(), height.toFloat(), paint)
            temp.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
            bitmap.recycle()
            val exif = androidx.exifinterface.media.ExifInterface(temp.path)
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION, "6")
            exif.saveAttributes()
            resolver.openOutputStream(uri)!!.use { out -> temp.inputStream().use { out.write(it.readBytes()) } }
        } finally { temp.delete() }
    }

    private fun exifText(ms: Long): String {
        val c = java.util.Calendar.getInstance()
        c.timeInMillis = ms
        return "%04d:%02d:%02d %02d:%02d:%02d".format(
            Locale.US,
            c.get(java.util.Calendar.YEAR),
            c.get(java.util.Calendar.MONTH) + 1,
            c.get(java.util.Calendar.DAY_OF_MONTH),
            c.get(java.util.Calendar.HOUR_OF_DAY),
            c.get(java.util.Calendar.MINUTE),
            c.get(java.util.Calendar.SECOND),
        )
    }

    private fun describeIntegrity(): List<Map<String, Any>> {
        return subset("integrity").mapNotNull { value ->
            resolver.query(Uri.parse(value), arrayOf("_id", "volume_name", "bucket_id", "width", "height", "datetaken", "date_added", "date_modified", "_display_name"), null, null, null)?.use { c ->
                if (!c.moveToFirst()) return@use null
                val id = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(c.getString(1)), c.getLong(0)).toString()
                val name = c.getString(8) ?: ""
                mapOf(
                    "id" to id,
                    "group" to "${c.getString(1)}:${c.getString(2)}",
                    "kind" to when {
                        name.startsWith("integ_long") -> "long"
                        name.startsWith("integ_large") -> "large"
                        name.startsWith("integ_rot") -> "rotated"
                        name.startsWith("integ_gif") -> "gif"
                        name.startsWith("integ_corrupt") -> "corrupt"
                        name.startsWith("integ_old") -> "old"
                        name.startsWith("integ_fallback") -> "fallback"
                        name.startsWith("integ_tie") -> "tie"
                        name.startsWith("integ_sweep") -> "sweep"
                        name.startsWith("integ_same") -> "samename"
                        name.startsWith("perf_normal") -> "perfNormal"
                        name.startsWith("perf_large_b_") -> "perfLargeB"
                        name.startsWith("perf_large_") -> "perfLarge"
                        else -> "other"
                    },
                    "width" to c.getInt(3), "height" to c.getInt(4),
                    "datetaken" to c.getLong(5),
                    "dateAdded" to c.getLong(6),
                    "dateModified" to c.getLong(7),
                )
            }
        }
    }

    /** On-demand integrity fixtures for dynamic add/move/delete scenarios. */
    private fun dynamicInsert(path: String, count: Int, pendingFirst: Boolean): Map<String, Any> {
        val run = UUID.randomUUID().toString().take(8)
        val ids = mutableListOf<String>()
        repeat(count) { i ->
            val taken = System.currentTimeMillis() - i * 1000L
            val uri = insertFixture(pendingValues("integ_dyn_${run}_$i.jpg", path, 320, 240, taken), true)
            writeJpegWithExif(uri, 320, 240, i % 3, i + 20, taken)
            if (pendingFirst) finishPending(uri)
            val canonical = resolver.query(uri, arrayOf("_id", "volume_name"), null, null, null)?.use { c ->
                if (c.moveToFirst()) ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(c.getString(1)), c.getLong(0)).toString() else ""
            } ?: ""
            if (canonical.isNotEmpty()) ids.add(canonical)
        }
        return mapOf("ids" to ids.filter { it.isNotEmpty() })
    }

    private fun integrityMove(fromPath: String, toPath: String): String {
        val target = subset("integrity").firstOrNull { value ->
            resolver.query(Uri.parse(value), arrayOf(MediaStore.MediaColumns.RELATIVE_PATH), null, null, null)?.use { c ->
                c.moveToFirst() && c.getString(0)?.trimEnd('/') == fromPath
            } ?: false
        } ?: return "notFound"
        return try {
            resolver.update(Uri.parse(target), ContentValues().apply { put(MediaStore.Images.Media.RELATIVE_PATH, toPath) }, null, null)
            "moved"
        } catch (_: Exception) { "unsupported" }
    }

    /** Export samples for the performance run; independent of the bulk dataset.
     *  Idempotent across runs: a previous run's samples stay recorded and are
     *  reused instead of being duplicated. */
    private fun seedPerfSamples(): Map<String, Any> {
        val existingSample = subset("integrity").any { value ->
            resolver.query(Uri.parse(value), arrayOf("_display_name"), null, null, null)?.use { c ->
                c.moveToFirst() && (c.getString(0) ?: "").startsWith("perf_")
            } ?: false
        }
        if (existingSample) return mapOf("inserted" to 0, "reused" to true)
        val run = UUID.randomUUID().toString().take(8)
        val path = "Pictures/AlbumPerfSamples_$run"
        val now = System.currentTimeMillis()
        val normal = insertFixture(pendingValues("perf_normal_$run.jpg", path, 1200, 900, now - 1000), true)
        writeJpegWithExif(normal, 1200, 900, 1, 11, now - 1000); finishPending(normal)
        val large = insertFixture(pendingValues("perf_large_$run.jpg", path, 4000, 3000, now - 2000), true)
        writeJpegWithExif(large, 4000, 3000, 1, 12, now - 2000); finishPending(large)
        val largeB = insertFixture(pendingValues("perf_large_b_$run.jpg", path, 4000, 3000, now - 3000), true)
        writeJpegWithExif(largeB, 4000, 3000, 2, 13, now - 3000); finishPending(largeB)
        return mapOf("inserted" to 3)
    }

    /**
     * Behavior guard for the orphan sweep: every row present in the recorded
     * bookkeeping must survive sweepOrphans untouched. Seeds two tiny rows,
     * records them, sweeps, then verifies the recorded rows still exist and
     * removes the probe rows again.
     */
    private fun sweepProtectionProbe(): Map<String, Any> {
        val run = UUID.randomUUID().toString().take(8)
        val path = "Pictures/IntegritySweep_$run"
        val probeUris = mutableListOf<String>()
        repeat(2) { i ->
            val uri = insertFixture(pendingValues("integ_sweep_${run}_$i.jpg", path, 96, 64, 0), true)
            writeBitmap(uri, 96, 64, 0, i)
            finishPending(uri)
            probeUris.add(uri.toString())
        }
        val recordedBefore = subset("integrity").size
        val removedBySweep = sweepOrphans()
        val surviving = subset("integrity").count { value ->
            resolver.query(Uri.parse(value), arrayOf("_id"), null, null, null)?.use { it.moveToFirst() } ?: false
        }
        // Content URIs never carry the display name, so cleanup must use the
        // URIs captured at insert time, not a name filter.
        probeUris.forEach { deleteRecorded(it, "integrity") }
        return mapOf(
            "recordedBefore" to recordedBefore,
            "removedBySweep" to removedBySweep,
            "survivingRecorded" to surviving,
        )
    }

    /**
     * Bulk dataset for large-library runs. Cumulative target; deletes and
     * regenerates only when the recorded count does not match the target.
     * Content is deterministic per index; 70% 1MP / 25% 4MP / 5% 12MP with
     * mixed orientation and complexity.
     */
    private fun generateDataset(target: Int): Map<String, Any> {
        val current = subset("dataset")
        if (current.size > target) {
            val failed = mutableListOf<String>()
            for (value in current) {
                val uri = Uri.parse(value)
                var ok = false
                resolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst() && c.getString(0) == app.packageName) { ok = resolver.delete(uri, null, null) == 1 }
                }
                if (!ok) failed.add(value)
            }
            if (failed.isNotEmpty()) error("dataset cleanup left ${failed.size} resources")
            val uris = owned(); uris.removeAll(current.toSet())
            prefs.edit().putStringSet("dataset", emptySet()).putStringSet("uris", uris).commit()
        }
        val existing = subset("dataset")
        if (existing.size == target) return mapOf("generated" to 0, "total" to target)
        val run = UUID.randomUUID().toString().take(8)
        val dirNames = ('a'..'f').map { "AlbumPerf_${run}_$it" }.toList()
        val done = AtomicInteger(existing.size)
        val errors = ConcurrentLinkedQueue<String>()
        val uris = owned().toMutableSet()
        val recorded = existing.toMutableSet()
        fun persist() = synchronized(prefs) {
            prefs.edit()
                .putStringSet("uris", uris.toSet())
                .putStringSet("dataset", recorded.toSet())
                .commit()
            File(app.filesDir, "album_test_phase.txt").writeText("dataset_${done.get()}/$target")
        }
        val pool = Executors.newFixedThreadPool(3)
        val start = SystemClock.elapsedRealtime()
        for (i in existing.size until target) {
            pool.execute {
                if (errors.isNotEmpty()) return@execute
                try {
                    val sizeClass = i % 100
                    val portrait = i % 2 == 1
                    val dims = when {
                        sizeClass < 70 -> if (portrait) 900 to 1200 else 1200 to 900
                        sizeClass < 95 -> if (portrait) 1600 to 2400 else 2400 to 1600
                        else -> if (portrait) 3000 to 4000 else 4000 to 3000
                    }
                    // Deterministic times: every 101st falls back to date_added,
                    // every 37th repeats the previous timestamp (tie-break).
                    val datetaken = when {
                        i % 101 == 0 -> 0L
                        else -> 1_660_000_000_000L + (if (i % 37 == 0) i - 1 else i) * 1000L
                    }
                    val values = pendingValues("perf_${run}_%05d.jpg".format(Locale.US, i), "Pictures/${dirNames[i % dirNames.size]}", dims.first, dims.second, datetaken)
                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("insert")
                    writeJpegWithExif(uri, dims.first, dims.second, i % 3, (i * 13) % 97, datetaken)
                    finishPending(uri)
                    synchronized(prefs) {
                        uris.add(uri.toString()); recorded.add(uri.toString())
                        done.incrementAndGet()
                        if (done.get() % 100 == 0) persist()
                    }
                } catch (e: Exception) { errors.add(e.message ?: "generate failed") }
            }
        }
        pool.shutdown()
        pool.awaitTermination(3, TimeUnit.HOURS)
        persist()
        if (errors.isNotEmpty()) error("dataset generation failed: ${errors.first()}")
        return mapOf(
            "generated" to (target - existing.size),
            "total" to subset("dataset").size,
            "elapsedMs" to (SystemClock.elapsedRealtime() - start),
        )
    }

    private fun datasetStats(): Map<String, Any> {
        var bytes = 0L
        var rows = 0
        for (value in subset("dataset")) {
            resolver.query(Uri.parse(value), arrayOf("_size"), null, null, null)?.use { c ->
                if (c.moveToFirst()) { bytes += c.getLong(0); rows++ }
            }
        }
        return mapOf("rows" to rows, "bytes" to bytes)
    }

    private fun meminfo(): Map<String, Any> {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        return mapOf(
            "totalPss" to info.totalPss,
            "dalvikPss" to info.dalvikPss,
            "nativePss" to info.nativePss,
            "nativeHeapAllocated" to Debug.getNativeHeapAllocatedSize(),
            "uptimeMs" to SystemClock.uptimeMillis(),
        )
    }

    private fun exportCacheBytes(): Long {
        val root = File(app.cacheDir, "portable_album_exports")
        if (!root.exists()) return 0L
        return root.walkBottomUp().filter { it.isFile }.sumOf { it.length() }
    }

    /**
     * Minimal valid single-frame GIF89a, 8x8 solid color, two-entry global
     * color table. Literal-only LZW stream whose code-width growth mirrors the
     * decoder's deterministic counter.
     */
    private fun gifBytes(): ByteArray {
        val width = 8; val height = 8
        val out = ArrayList<Byte>(160)
        fun b(v: Int) { out.add(v.toByte()) }
        fun le16(v: Int) { b(v and 0xFF); b((v shr 8) and 0xFF) }
        "GIF89a".forEach { out.add(it.code.toByte()) }
        le16(width); le16(height)
        b(0x80); b(0); b(0)                 // GCT present, 2 entries
        b(0); b(0); b(0)                    // color 0: black
        b(0xC8); b(0x3C); b(0x3C)           // color 1: red
        b(0x2C); le16(0); le16(0); le16(width); le16(height); b(0)
        val minCode = 2
        b(minCode)
        // LZW literal stream with mirrored width growth.
        var codeWidth = minCode + 1
        var next = (1 shl minCode) + 2
        var acc = 0L; var bits = 0
        val body = ArrayList<Byte>()
        fun emit(code: Int, first: Boolean) {
            acc = acc or (code.toLong() shl bits); bits += codeWidth
            while (bits >= 8) { body.add((acc and 0xFF).toByte()); acc = acc shr 8; bits -= 8 }
            if (!first) {
                next++
                if (next >= (1 shl codeWidth) && codeWidth < 12) codeWidth++
            }
        }
        emit(1 shl minCode, true) // clear
        var first = true
        repeat(width * height) { emit(1, first); first = false }
        emit((1 shl minCode) + 1, false) // EOI
        if (bits > 0) body.add(acc.toByte())
        var i = 0
        while (i < body.size) {
            val n = minOf(255, body.size - i)
            b(n); repeat(n) { b(body[i + it].toInt() and 0xFF) }
            i += n
        }
        b(0) // block terminator
        b(0x3B) // trailer
        return out.toByteArray()
    }
}
