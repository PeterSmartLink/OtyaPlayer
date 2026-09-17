package com.otyaplayer.app

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Native direct-update bridge for website-distributed Otya APK builds. */
class UpdateDownloads(private val activity: Activity) {
    companion object {
        private const val APK_CONTENT_TYPE = "application/vnd.android.package-archive"
        private val TAG_RE = Regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+[1-9][0-9]*$")
        private val OFFICIAL_HOSTS = setOf("petersmartlink.com", "www.petersmartlink.com")
        private val APK_PATHS = setOf("/apk/arm64", "/apk/arm32")
    }

    private fun manager(): DownloadManager =
        activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun prefs() =
        activity.getSharedPreferences("otya_update_downloads", Context.MODE_PRIVATE)

    private fun requireTag(tag: String) {
        require(TAG_RE.matches(tag))
    }

    private fun requireOfficialApk(uri: Uri, tag: String) {
        require(uri.scheme == "https" && uri.host in OFFICIAL_HOSTS)
        require(uri.userInfo == null && (uri.port == -1 || uri.port == 443) && uri.fragment == null)
        require(uri.path in APK_PATHS)
        requireTag(tag)
        require(uri.queryParameterNames == setOf("tag") && uri.getQueryParameters("tag") == listOf(tag))
    }

    private fun snapshot(tag: String): Map<String, Any> {
        requireTag(tag)
        val manager = manager()
        val id = prefs().getLong(tag, -1)
        if (id == -1L) return mapOf("status" to "none")

        manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (cursor == null || !cursor.moveToFirst()) return mapOf("status" to "missing")
            val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (state == DownloadManager.STATUS_SUCCESSFUL) {
                val readable = try {
                    manager.openDownloadedFile(id)?.use { true } ?: false
                } catch (_: Exception) {
                    false
                }
                if (!readable) return mapOf("status" to "missing")
            }
            val status = when (state) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "complete"
                DownloadManager.STATUS_FAILED -> "failed"
                else -> "unknown"
            }
            return mapOf(
                "status" to status,
                "downloaded" to cursor.getLong(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                ),
                "total" to cursor.getLong(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                ),
            )
        }
    }

    private fun enqueue(url: String, tag: String): Long {
        val uri = Uri.parse(url)
        requireOfficialApk(uri, tag)

        val manager = manager()
        val prefs = prefs()
        val previous = prefs.getLong(tag, -1)
        if (previous != -1L) {
            if (snapshot(tag)["status"] in setOf("pending", "running", "paused", "complete")) {
                return previous
            }
            manager.remove(previous)
        }

        val request = DownloadManager.Request(uri)
            .setTitle("Otya update")
            .setDescription("Downloading the verified Otya update.")
            .setMimeType(APK_CONTENT_TYPE)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            request.setDestinationInExternalPublicDir(
                Environment.DIRECTORY_DOWNLOADS,
                "Otya-$tag-${System.currentTimeMillis()}.apk",
            )
        } else {
            request.setDestinationInExternalFilesDir(
                activity,
                Environment.DIRECTORY_DOWNLOADS,
                "Otya-$tag-${System.currentTimeMillis()}.apk",
            )
        }

        val id = manager.enqueue(request)
        prefs.edit().putLong(tag, id).apply()
        return id
    }

    /**
     * Opens Android's trusted package installer for the completed Otya APK.
     * Android still requires an explicit user confirmation; Otya never silently
     * installs or replaces an application package.
     */
    private fun openInstaller(tag: String): String {
        requireTag(tag)
        require(snapshot(tag)["status"] == "complete")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            val permissionIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
            activity.startActivity(permissionIntent)
            return "permission_required"
        }

        val id = prefs().getLong(tag, -1)
        require(id != -1L)
        val apkUri = manager().getUriForDownloadedFile(id)
            ?: throw IllegalStateException("Downloaded APK is unavailable")

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_CONTENT_TYPE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        require(installIntent.resolveActivity(activity.packageManager) != null)
        activity.startActivity(installIntent)
        return "installer_opened"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.otyaplayer.app/updates").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "download" -> {
                        val url = call.argument<String>("url") ?: ""
                        val tag = call.argument<String>("tag") ?: ""
                        result.success(enqueue(url, tag))
                    }
                    "status" -> {
                        val tag = call.argument<String>("tag") ?: ""
                        result.success(snapshot(tag))
                    }
                    "install" -> {
                        val tag = call.argument<String>("tag") ?: ""
                        result.success(openInstaller(tag))
                    }
                    "showDownloads" -> {
                        activity.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error(
                    "update_unavailable",
                    "Android could not continue this Otya update. Please try again.",
                    null,
                )
            }
        }
    }
}
