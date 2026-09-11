package com.otyaplayer.app

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** User-requested downloads only; Android owns background transfer and install UI. */
class UpdateDownloads(private val activity: Activity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.otyaplayer.app/updates").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "download" -> {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        val tag = call.argument<String>("tag") ?: ""
                        require(uri.scheme == "https" && uri.host in setOf("petersmartlink.com", "www.petersmartlink.com"))
                        require(uri.userInfo == null && (uri.port == -1 || uri.port == 443) && uri.fragment == null)
                        require(uri.path in setOf("/apk/arm64", "/apk/arm32"))
                        require(Regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+[1-9][0-9]*$").matches(tag))
                        require(uri.queryParameterNames == setOf("tag") && uri.getQueryParameters("tag") == listOf(tag))
                        val manager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                        val prefs = activity.getSharedPreferences("otya_update_downloads", Context.MODE_PRIVATE)
                        val previous = prefs.getLong(tag, -1)
                        if (previous != -1L) {
                            manager.query(DownloadManager.Query().setFilterById(previous)).use { cursor ->
                                if (cursor != null && cursor.moveToFirst() &&
                                    cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) != DownloadManager.STATUS_FAILED) {
                                    result.success(previous)
                                    return@setMethodCallHandler
                                }
                            }
                            manager.remove(previous)
                        }
                        val request = DownloadManager.Request(uri)
                            .setTitle("Otya update")
                            .setDescription("Tap when complete to open your Android update.")
                            .setMimeType("application/vnd.android.package-archive")
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Otya-$tag.apk")
                        } else {
                            request.setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS, "Otya-$tag.apk")
                        }
                        val id = manager.enqueue(request)
                        prefs.edit().putLong(tag, id).apply()
                        result.success(id)
                    }
                    "showDownloads" -> {
                        activity.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("download_unavailable", "Android could not start or open this download. Please try again.", null)
            }
        }
    }
}
