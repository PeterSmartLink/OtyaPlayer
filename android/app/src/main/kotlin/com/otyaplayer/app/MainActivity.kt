package com.otyaplayer.app

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * OTYA's Android bridge.
 *
 * Native Android owns only platform capabilities that Flutter cannot provide
 * reliably itself: MediaStore, PiP, device integration, large-file sharing,
 * lightweight local media muxing and the Android equalizer bridge.
 * Playback, updates, navigation and product state remain owned by Flutter.
 */
class MainActivity : AudioServiceFragmentActivity() {

    private val pipChannel = "com.otyaplayer.app/pip"
    private val mediaChannel = "com.otyaplayer.app/media_store"
    private val fileChannel = "com.otyaplayer.app/file_ops"
    private val eqChannel = "com.otyaplayer.app/equalizer"
    private val phoneChannel = "com.otyaplayer.app/phone_state"
    private val ffmpegChannel = "com.otyaplayer.app/ffmpeg"
    private val mediaEventChannel = "com.otyaplayer.app/media_events"
    private val deviceIdChannel = "com.otyaplayer.app/device_id"
    private val brightnessChannel = "com.otyaplayer.app/brightness"
    private val volumeChannel = "com.otyaplayer.app/volume"
    private val shareChannel = "com.otyaplayer.app/share"

    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var mediaJob: Job? = null

    @Volatile
    private var isVideoPlaying = false

    private var equalizer: android.media.audiofx.Equalizer? = null

    @Suppress("DEPRECATION")
    private var phoneStateListener: android.telephony.PhoneStateListener? = null
    private var telephonyManager: android.telephony.TelephonyManager? = null
    private var telephonyCallback: android.telephony.TelephonyCallback? = null

    private var mediaObserver: ContentObserver? = null
    private var mediaEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UpdateDownloads(this).register(flutterEngine.dartExecutor.binaryMessenger)
        createAudioNotificationChannel()
        configurePip(flutterEngine)
        configureMediaStore(flutterEngine)
        configureMediaEvents(flutterEngine)
        configurePhoneState(flutterEngine)
        configureEqualizer(flutterEngine)
        configureFileOperations(flutterEngine)
        configureMediaTools(flutterEngine)
        configureDeviceId(flutterEngine)
        configureBrightness(flutterEngine)
        configureVolume(flutterEngine)
        configureSharing(flutterEngine)
    }

    private fun createAudioNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = android.app.NotificationChannel(
            "com.otyaplayer.app.audio",
            "Otya — Now Playing",
            android.app.NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Media playback controls and lock screen notification"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        getSystemService(android.app.NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun configurePip(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        val width = call.argument<Int>("width") ?: 16
                        val height = call.argument<Int>("height") ?: 9
                        enterPipMode(width, height, result)
                    }
                    "isPipSupported" -> result.success(isPipSupported())
                    "setVideoPlaying" -> {
                        isVideoPlaying = call.argument<Boolean>("playing") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureMediaStore(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "queryAudio" -> result.success(queryAudio())
                    "queryVideo" -> result.success(queryVideo())
                    "getVideoThumbnail" -> result.success(
                        getVideoThumbnail(
                            call.argument<String>("path") ?: "",
                            call.argument<String>("id") ?: "",
                        ),
                    )
                    "getAlbumArt" -> result.success(
                        getAlbumArt(call.argument<String>("albumId") ?: ""),
                    )
                    "triggerScan" -> {
                        triggerMediaScan(call.argument<String>("path") ?: "")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureMediaEvents(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, mediaEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    mediaEventSink = sink
                    registerMediaObserver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterMediaObserver()
                    mediaEventSink = null
                }
            })
    }

    private fun configurePhoneState(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, phoneChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPauseDuringCalls" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        if (enabled && ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.READ_PHONE_STATE,
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            registerPhoneListener()
                        } else {
                            unregisterPhoneListener()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureEqualizer(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, eqChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBands" -> {
                        @Suppress("UNCHECKED_CAST")
                        val gains = call.argument<List<Double>>("gains") ?: emptyList()
                        applyEqBands(gains)
                        result.success(null)
                    }
                    "release" -> {
                        equalizer?.release()
                        equalizer = null
                        result.success(null)
                    }
                    "getAudioSessionId" -> result.success(0)
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureFileOperations(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteFile" -> result.success(
                        deleteMediaFile(call.argument<String>("path") ?: ""),
                    )
                    "renameFile" -> result.success(
                        renameFile(
                            call.argument<String>("path") ?: "",
                            call.argument<String>("newName") ?: "",
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureMediaTools(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ffmpegChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "trimVideo" -> {
                        if (mediaJob?.isActive == true) {
                            result.error("BUSY", "Another media tool is already running", null)
                            return@setMethodCallHandler
                        }
                        val path = call.argument<String>("path") ?: ""
                        val startMs = call.argument<Int>("startMs") ?: 0
                        val endMs = call.argument<Int>("endMs") ?: 30_000
                        mediaJob = ioScope.launch {
                            val output = try {
                                trimVideo(path, startMs.toLong(), endMs.toLong())
                            } catch (_: CancellationException) {
                                null
                            }
                            runOnUiThread {
                                if (output != null) {
                                    result.success(output)
                                } else if (mediaJob?.isCancelled == true) {
                                    result.error("CANCELLED", "Operation cancelled", null)
                                } else {
                                    result.error("TRIM_FAILED", "Trim failed", null)
                                }
                            }
                        }
                    }
                    "extractAudio" -> {
                        if (mediaJob?.isActive == true) {
                            result.error("BUSY", "Another media tool is already running", null)
                            return@setMethodCallHandler
                        }
                        val path = call.argument<String>("path") ?: ""
                        mediaJob = ioScope.launch {
                            val output = try {
                                extractAudio(path)
                            } catch (_: CancellationException) {
                                null
                            }
                            runOnUiThread {
                                if (output != null) {
                                    result.success(output)
                                } else if (mediaJob?.isCancelled == true) {
                                    result.error("CANCELLED", "Operation cancelled", null)
                                } else {
                                    result.error("EXTRACT_FAILED", "Extract failed", null)
                                }
                            }
                        }
                    }
                    "cancel" -> {
                        mediaJob?.cancel()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureDeviceId(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceIdChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> result.success(
                        Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureBrightness(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBrightness" -> {
                        val value = call.argument<Double>("value")?.toFloat() ?: .5f
                        val params = window.attributes
                        params.screenBrightness = value.coerceIn(.01f, 1f)
                        window.attributes = params
                        result.success(null)
                    }
                    "getBrightness" -> {
                        val current = window.attributes.screenBrightness
                        result.success((if (current < 0) .5f else current).toDouble())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureVolume(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannel)
            .setMethodCallHandler { call, result ->
                val manager = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
                val maxVolume = manager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                    .coerceAtLeast(1)
                when (call.method) {
                    "setVolume" -> {
                        val value = (call.argument<Double>("value") ?: .5).coerceIn(0.0, 1.0)
                        manager.setStreamVolume(
                            android.media.AudioManager.STREAM_MUSIC,
                            (value * maxVolume).toInt().coerceIn(0, maxVolume),
                            0,
                        )
                        result.success(null)
                    }
                    "getVolume" -> result.success(
                        manager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
                            .toDouble() / maxVolume.toDouble(),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureSharing(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "shareFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path") ?: ""
                val text = call.argument<String>("text")
                try {
                    shareFile(path, text)
                    result.success(null)
                } catch (error: Exception) {
                    Log.e("NativeShare", "Share failed: ${error.message}")
                    result.error("SHARE_FAILED", "OTYA could not share that file", null)
                }
            }
    }

    private fun shareFile(path: String, text: String?) {
        val file = File(path)
        require(path.isNotBlank() && file.exists() && file.isFile) {
            "Share source does not exist"
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.share",
            file,
        )
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            if (!text.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, text)
            clipData = ClipData.newRawUri(file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Share with"))
    }

    private fun registerMediaObserver() {
        if (mediaObserver != null) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                mediaEventSink?.success("changed")
            }
        }
        try {
            contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                true,
                observer,
            )
            contentResolver.registerContentObserver(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                true,
                observer,
            )
            mediaObserver = observer
        } catch (error: SecurityException) {
            Log.w("MediaObserver", "Media observer unavailable: ${error.message}")
        }
    }

    private fun unregisterMediaObserver() {
        mediaObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
        }
        mediaObserver = null
    }

    private fun triggerMediaScan(path: String) {
        if (path.isBlank() || path.startsWith("content://")) return
        try {
            MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
        } catch (_: Exception) {
        }
    }

    private suspend fun trimVideo(inputPath: String, startMs: Long, endMs: Long): String? {
        if (inputPath.isBlank() || endMs <= startMs) return null
        val temp = File.createTempFile("otya_trim_", ".mp4", cacheDir)
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(inputPath)
            muxer = MediaMuxer(temp.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = mutableMapOf<Int, Int>()
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/") || mime.startsWith("video/")) {
                    trackMap[index] = muxer.addTrack(format)
                }
            }
            if (trackMap.isEmpty()) return null
            muxer.start()
            muxerStarted = true

            val startUs = startMs.coerceAtLeast(0) * 1_000L
            val endUs = endMs * 1_000L
            val buffer = ByteBuffer.allocate(1024 * 1024)
            val info = android.media.MediaCodec.BufferInfo()

            for ((sourceTrack, targetTrack) in trackMap) {
                currentCoroutineContext().ensureActive()
                for (index in 0 until extractor.trackCount) {
                    try {
                        extractor.unselectTrack(index)
                    } catch (_: Exception) {
                    }
                }
                extractor.selectTrack(sourceTrack)
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                var firstPts: Long? = null

                while (true) {
                    currentCoroutineContext().ensureActive()
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    val pts = extractor.sampleTime
                    if (pts < 0 || pts > endUs) break
                    if (firstPts == null) firstPts = pts
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = (pts - firstPts!!).coerceAtLeast(0)
                    info.flags = extractor.sampleFlags
                    muxer.writeSampleData(targetTrack, buffer, info)
                    extractor.advance()
                }
            }

            muxer.stop()
            muxerStarted = false
            val name = "OTYA_trim_${System.currentTimeMillis()}.mp4"
            return publishGeneratedMedia(
                temp = temp,
                displayName = name,
                mimeType = "video/mp4",
                video = true,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Log.e("MediaTools", "trimVideo failed: ${error.message}")
            return null
        } finally {
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (_: Exception) {
                }
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            if (temp.exists()) temp.delete()
        }
    }

    private suspend fun extractAudio(inputPath: String): String? {
        if (inputPath.isBlank()) return null
        val temp = File.createTempFile("otya_audio_", ".m4a", cacheDir)
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(inputPath)
            var audioTrack = -1
            var audioFormat: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrack = index
                    audioFormat = format
                    break
                }
            }
            if (audioTrack < 0 || audioFormat == null) return null

            extractor.selectTrack(audioTrack)
            muxer = MediaMuxer(temp.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val targetTrack = muxer.addTrack(audioFormat)
            muxer.start()
            muxerStarted = true

            val buffer = ByteBuffer.allocate(512 * 1024)
            val info = android.media.MediaCodec.BufferInfo()
            var firstPts: Long? = null
            while (true) {
                currentCoroutineContext().ensureActive()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val pts = extractor.sampleTime
                if (pts < 0) break
                if (firstPts == null) firstPts = pts
                info.offset = 0
                info.size = size
                info.presentationTimeUs = (pts - firstPts!!).coerceAtLeast(0)
                info.flags = extractor.sampleFlags
                muxer.writeSampleData(targetTrack, buffer, info)
                extractor.advance()
            }

            muxer.stop()
            muxerStarted = false
            val name = "OTYA_audio_${System.currentTimeMillis()}.m4a"
            return publishGeneratedMedia(
                temp = temp,
                displayName = name,
                mimeType = "audio/mp4",
                video = false,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Log.e("MediaTools", "extractAudio failed: ${error.message}")
            return null
        } finally {
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (_: Exception) {
                }
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            if (temp.exists()) temp.delete()
        }
    }

    private fun publishGeneratedMedia(
        temp: File,
        displayName: String,
        mimeType: String,
        video: Boolean,
    ): String? {
        if (!temp.exists() || temp.length() <= 0L) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (video) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val directory = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$directory/OTYA")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(collection, values) ?: return null
            return try {
                contentResolver.openOutputStream(uri, "w")?.use { output ->
                    temp.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("Could not open MediaStore output")

                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                mediaEventSink?.success("changed")
                mediaPathForUri(uri) ?: "$directory/OTYA/$displayName"
            } catch (error: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                Log.e("MediaTools", "Could not publish output: ${error.message}")
                null
            }
        }

        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(
            if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC,
        )
        val outputDir = File(base, "OTYA").apply { mkdirs() }
        val outputFile = uniqueFile(outputDir, displayName)
        return try {
            temp.copyTo(outputFile, overwrite = false)
            triggerMediaScan(outputFile.absolutePath)
            outputFile.absolutePath
        } catch (error: Exception) {
            Log.e("MediaTools", "Could not publish legacy output: ${error.message}")
            null
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        val direct = File(directory, name)
        if (!direct.exists()) return direct
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        for (index in 2..999) {
            val candidate = File(directory, "$base ($index)$extension")
            if (!candidate.exists()) return candidate
        }
        return File(directory, "${base}_${System.currentTimeMillis()}$extension")
    }

    private fun mediaPathForUri(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val column = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (column >= 0) cursor.getString(column) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun queryAudio(): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
        )
        val selection = "${MediaStore.Audio.Media.SIZE} >= 10240 AND ${MediaStore.Audio.Media.DURATION} > 0"
        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val name = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val data = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val size = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val date = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumId = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(data) ?: continue
                    items.add(
                        mapOf(
                            "id" to cursor.getLong(id).toString(),
                            "displayName" to (cursor.getString(name) ?: ""),
                            "path" to path,
                            "durationMs" to cursor.getLong(duration),
                            "size" to cursor.getLong(size),
                            "dateAdded" to cursor.getLong(date),
                            "artist" to cursor.getString(artist),
                            "album" to cursor.getString(album),
                            "albumId" to cursor.getLong(albumId).toString(),
                            "isVideo" to false,
                        ),
                    )
                }
            }
        } catch (error: SecurityException) {
            Log.w("MediaStore", "Audio query denied: ${error.message}")
        }
        return items
    }

    private fun queryVideo(): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
        )
        val selection = "${MediaStore.Video.Media.SIZE} >= 10240 AND ${MediaStore.Video.Media.DURATION} > 0"
        try {
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                "${MediaStore.Video.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val id = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val name = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val data = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                val duration = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val size = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val date = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(data) ?: continue
                    items.add(
                        mapOf(
                            "id" to cursor.getLong(id).toString(),
                            "displayName" to (cursor.getString(name) ?: ""),
                            "path" to path,
                            "durationMs" to cursor.getLong(duration),
                            "size" to cursor.getLong(size),
                            "dateAdded" to cursor.getLong(date),
                            "artist" to null,
                            "album" to null,
                            "albumId" to null,
                            "isVideo" to true,
                        ),
                    )
                }
            }
        } catch (error: SecurityException) {
            Log.w("MediaStore", "Video query denied: ${error.message}")
        }
        return items
    }

    private fun getVideoThumbnail(videoPath: String, videoId: String): String? {
        val cacheKey = (videoId.ifBlank { videoPath }).hashCode().toUInt().toString(16)
        val thumbDir = File(cacheDir, "video_thumbs_v2").apply { mkdirs() }
        val thumbFile = File(thumbDir, "$cacheKey.jpg")
        if (thumbFile.exists() && thumbFile.length() > 0L) return thumbFile.absolutePath

        var bitmap: Bitmap? = null
        val numericId = videoId.toLongOrNull()
        if (numericId != null) {
            bitmap = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    contentResolver.loadThumbnail(
                        ContentUris.withAppendedId(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            numericId,
                        ),
                        Size(720, 405),
                        null,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    MediaStore.Video.Thumbnails.getThumbnail(
                        contentResolver,
                        numericId,
                        MediaStore.Video.Thumbnails.MINI_KIND,
                        null,
                    )
                }
            } catch (_: Exception) {
                null
            }
        }

        if (bitmap == null && videoPath.isNotBlank()) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(videoPath)
                val durationMs = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                )?.toLongOrNull() ?: 0L
                // Avoid choosing a black/logo frame at the very beginning when
                // possible. Ten percent is representative for short/long local
                // clips, bounded so thumbnail generation stays predictable.
                val frameUs = if (durationMs > 0L) {
                    (durationMs * 100L).coerceIn(1_000_000L, 30_000_000L)
                } else {
                    1_000_000L
                }
                bitmap = retriever.getFrameAtTime(
                    frameUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                ) ?: retriever.frameAtTime
            } catch (_: Exception) {
                bitmap = null
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {
                }
            }
        }

        return try {
            bitmap?.let {
                FileOutputStream(thumbFile).use { output ->
                    it.compress(Bitmap.CompressFormat.JPEG, 90, output)
                }
                if (thumbFile.length() > 0L) thumbFile.absolutePath else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getAlbumArt(albumId: String): String? {
        if (albumId.isBlank()) return null
        return try {
            val artDir = File(cacheDir, "album_art").apply { mkdirs() }
            val artFile = File(artDir, "$albumId.jpg")
            if (artFile.exists() && artFile.length() > 0L) return artFile.absolutePath
            val artUri = Uri.parse("content://media/external/audio/albumart/$albumId")
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    contentResolver.loadThumbnail(artUri, Size(300, 300), null)
                } catch (_: Exception) {
                    null
                }
            } else {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(this, artUri)
                    retriever.embeddedPicture?.let {
                        android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)
                    }
                } catch (_: Exception) {
                    null
                } finally {
                    try {
                        retriever.release()
                    } catch (_: Exception) {
                    }
                }
            }
            bitmap?.let {
                FileOutputStream(artFile).use { output ->
                    it.compress(Bitmap.CompressFormat.JPEG, 85, output)
                }
                artFile.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun findMediaUri(path: String): Uri? {
        if (path.isBlank()) return null
        return try {
            contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns._ID),
                "${MediaStore.Files.FileColumns.DATA} = ?",
                arrayOf(path),
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val idColumn = cursor.getColumnIndex(MediaStore.Files.FileColumns._ID)
                if (idColumn < 0) return@use null
                ContentUris.withAppendedId(
                    MediaStore.Files.getContentUri("external"),
                    cursor.getLong(idColumn),
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteMediaFile(path: String): Boolean {
        return try {
            val uri = findMediaUri(path)
            val deleted = if (uri != null) contentResolver.delete(uri, null, null) > 0 else false
            val file = File(path)
            val fallback = if (!deleted && file.exists()) file.delete() else deleted
            if (fallback) triggerMediaScan(path)
            fallback
        } catch (error: SecurityException) {
            Log.w("FileOps", "Delete requires user consent: ${error.message}")
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun renameFile(path: String, newName: String): String? {
        val cleanName = newName.replace('/', '_').replace('\\', '_').trim()
        if (path.isBlank() || cleanName.isBlank()) return null
        return try {
            val uri = findMediaUri(path)
            if (uri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, cleanName)
                }
                if (contentResolver.update(uri, values, null, null) > 0) {
                    val parent = File(path).parent ?: return cleanName
                    return File(parent, cleanName).absolutePath
                }
            }
            val file = File(path)
            if (!file.exists()) return null
            val destination = File(file.parent ?: return null, cleanName)
            if (!file.renameTo(destination)) return null
            triggerMediaScan(path)
            triggerMediaScan(destination.absolutePath)
            destination.absolutePath
        } catch (error: SecurityException) {
            Log.w("FileOps", "Rename requires user consent: ${error.message}")
            null
        } catch (_: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun registerPhoneListener() {
        if (telephonyManager == null) {
            telephonyManager = getSystemService(TELEPHONY_SERVICE)
                as? android.telephony.TelephonyManager
        }
        val manager = telephonyManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (telephonyCallback != null) return
            val callback = object : android.telephony.TelephonyCallback(),
                android.telephony.TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    emitCallState(state)
                }
            }
            telephonyCallback = callback
            try {
                manager.registerTelephonyCallback(mainExecutor, callback)
            } catch (error: Exception) {
                telephonyCallback = null
                Log.w("PhoneState", "Could not register callback: ${error.message}")
            }
            return
        }

        if (phoneStateListener != null) return
        phoneStateListener = object : android.telephony.PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                emitCallState(state)
            }
        }
        try {
            manager.listen(
                phoneStateListener,
                android.telephony.PhoneStateListener.LISTEN_CALL_STATE,
            )
        } catch (error: Exception) {
            phoneStateListener = null
            Log.w("PhoneState", "Could not register listener: ${error.message}")
        }
    }

    private fun emitCallState(state: Int) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, phoneChannel).invokeMethod(
                "callState",
                mapOf("state" to state),
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun unregisterPhoneListener() {
        val manager = telephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyCallback?.let { callback ->
                try {
                    manager?.unregisterTelephonyCallback(callback)
                } catch (_: Exception) {
                }
            }
            telephonyCallback = null
        } else {
            phoneStateListener?.let { listener ->
                try {
                    manager?.listen(listener, android.telephony.PhoneStateListener.LISTEN_NONE)
                } catch (_: Exception) {
                }
            }
            phoneStateListener = null
        }
    }

    private fun applyEqBands(gains: List<Double>) {
        try {
            if (equalizer == null) {
                equalizer = android.media.audiofx.Equalizer(0, 0).apply { enabled = true }
            }
            val eq = equalizer ?: return
            val range = eq.bandLevelRange
            gains.take(eq.numberOfBands.toInt()).forEachIndexed { index, gainDb ->
                val level = (gainDb * 100).toInt().coerceIn(
                    range[0].toInt(),
                    range[1].toInt(),
                ).toShort()
                eq.setBandLevel(index.toShort(), level)
            }
        } catch (error: Exception) {
            Log.w("Equalizer", "Could not apply bands: ${error.message}")
        }
    }

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPipMode(width: Int, height: Int, result: MethodChannel.Result) {
        if (!isPipSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("PIP_UNSUPPORTED", "PiP requires Android 8.0+", null)
            return
        }
        try {
            val safeWidth = width.coerceAtLeast(1)
            val safeHeight = height.coerceAtLeast(1)
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(safeWidth, safeHeight))
                    .build(),
            )
            result.success(true)
        } catch (error: Exception) {
            result.error("PIP_ERROR", error.message, null)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!isPipSupported() || !isVideoPlaying || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build(),
            )
        } catch (_: Exception) {
        }
    }

    override fun onPause() {
        super.onPause()
        if (!isInPictureInPictureMode && isVideoPlaying) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, pipChannel).invokeMethod("playerPause", null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, pipChannel).invokeMethod("playerResume", null)
        }
    }

    override fun onDestroy() {
        mediaJob?.cancel()
        ioScope.cancel()
        unregisterMediaObserver()
        unregisterPhoneListener()
        try {
            equalizer?.release()
        } catch (_: Exception) {
        }
        equalizer = null
        super.onDestroy()
    }
}
