package com.petersmartlink.otya_transfer_android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Narrow Android bridge for OTYA Transfer.
 *
 * This plugin owns only the Android APIs Dart cannot provide reliably:
 * LocalOnlyHotspot lifecycle and inspection of the installed APK layout.
 * File transport, tokens, QR payloads and receive policy remain owned by Dart.
 */
class OtyaTransferAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotInfo: Map<String, Any?>? = null
    private var pendingHotspotResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingHotspotResult?.error(
            "HOTSPOT_CANCELLED",
            "OTYA Transfer closed before the hotspot finished starting.",
            null,
        )
        pendingHotspotResult = null
        stopHotspot()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startLocalOnlyHotspot" -> startHotspot(result)
            "stopLocalOnlyHotspot" -> {
                stopHotspot()
                result.success(null)
            }
            "getShareableApk" -> result.success(getShareableApk())
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            else -> result.notImplemented()
        }
    }

    private fun startHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error(
                "HOTSPOT_UNSUPPORTED",
                "Automatic offline hotspot requires Android 8.0 or newer.",
                null,
            )
            return
        }

        hotspotInfo?.let {
            result.success(it)
            return
        }

        if (pendingHotspotResult != null) {
            result.error(
                "HOTSPOT_BUSY",
                "OTYA is already starting an offline hotspot.",
                null,
            )
            return
        }

        if (!hasRequiredWifiPermission()) {
            result.error(
                "HOTSPOT_PERMISSION_REQUIRED",
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    "Nearby Wi-Fi permission is required to create an offline OTYA hotspot."
                } else {
                    "Location permission is required by this Android version to create a local-only hotspot."
                },
                null,
            )
            return
        }

        val wifiManager = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifiManager == null) {
            result.error("HOTSPOT_UNAVAILABLE", "Wi-Fi is not available on this device.", null)
            return
        }

        pendingHotspotResult = result
        try {
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        hotspotReservation = reservation
                        hotspotInfo = readHotspotInfo(reservation)
                        val pending = pendingHotspotResult
                        pendingHotspotResult = null
                        pending?.success(hotspotInfo)
                    }

                    override fun onStopped() {
                        hotspotReservation = null
                        hotspotInfo = null
                    }

                    override fun onFailed(reason: Int) {
                        hotspotReservation = null
                        hotspotInfo = null
                        val pending = pendingHotspotResult
                        pendingHotspotResult = null
                        pending?.error(
                            "HOTSPOT_FAILED",
                            hotspotFailureMessage(reason),
                            reason,
                        )
                    }
                },
                mainHandler,
            )
        } catch (error: SecurityException) {
            pendingHotspotResult = null
            result.error(
                "HOTSPOT_PERMISSION_REQUIRED",
                "Android blocked the offline hotspot because Wi-Fi permission is missing.",
                error.message,
            )
        } catch (error: Throwable) {
            pendingHotspotResult = null
            result.error(
                "HOTSPOT_FAILED",
                error.message ?: "Android could not create an offline hotspot.",
                null,
            )
        }
    }

    private fun stopHotspot() {
        val reservation = hotspotReservation
        hotspotReservation = null
        hotspotInfo = null
        runCatching { reservation?.close() }
    }

    private fun hasRequiredWifiPermission(): Boolean {
        if (context.checkSelfPermission(Manifest.permission.CHANGE_WIFI_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    @Suppress("DEPRECATION")
    private fun readHotspotInfo(
        reservation: WifiManager.LocalOnlyHotspotReservation,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation.softApConfiguration
            return mapOf(
                "ssid" to config.ssid,
                "passphrase" to config.passphrase,
                "securityType" to config.securityType,
            )
        }

        val config = reservation.wifiConfiguration
        return mapOf(
            "ssid" to cleanWifiValue(config?.SSID),
            "passphrase" to cleanWifiValue(config?.preSharedKey),
            "securityType" to -1,
        )
    }

    private fun cleanWifiValue(value: String?): String? =
        value?.trim()?.removeSurrounding("\"")?.takeIf { it.isNotBlank() }

    private fun hotspotFailureMessage(reason: Int): String = when (reason) {
        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED ->
            "Android does not allow a local hotspot on this device or profile."
        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
            "Another hotspot or Wi-Fi mode is already using the radio. Turn it off and try again."
        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
            "Android could not find a Wi-Fi channel for the offline hotspot."
        else -> "Android could not start the offline OTYA hotspot."
    }

    private fun getShareableApk(): Map<String, Any?> {
        val appInfo = context.applicationInfo
        val base = File(appInfo.sourceDir.orEmpty())
        val splits = appInfo.splitSourceDirs
            ?.map(::File)
            ?.filter { it.exists() }
            .orEmpty()

        if (!base.exists() || !base.isFile || base.length() <= 0L) {
            return mapOf(
                "available" to false,
                "splitCount" to splits.size,
                "reason" to "Android could not locate the installed Otya APK.",
            )
        }

        if (splits.isNotEmpty()) {
            return mapOf(
                "available" to false,
                "splitCount" to splits.size,
                "reason" to "This Otya install uses split APKs, so sharing only the base APK would create a broken installer.",
            )
        }

        return mapOf(
            "available" to true,
            "path" to base.absolutePath,
            "bytes" to base.length(),
            "splitCount" to 0,
            "reason" to null,
        )
    }

    companion object {
        private const val CHANNEL = "com.otyaplayer.app/transfer_android"
    }
}
