package com.scenicprints.phonecleanup

import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * The parts of this app that Dart cannot reach.
 *
 * Everything here is a read, a hand-off to a system settings screen, or a
 * MediaStore refresh. Nothing in this file deletes anything. Deletion happens
 * in Dart, on files the user has ticked, so there is exactly one place to audit.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "phone_cleanup/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "volume" -> result.success(volume())
                        "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                        "openAllFilesAccess" -> {
                            openAllFilesAccess(); result.success(true)
                        }
                        "hasUsageAccess" -> result.success(hasUsageAccess())
                        "openUsageAccess" -> {
                            open(Settings.ACTION_USAGE_ACCESS_SETTINGS); result.success(true)
                        }
                        "apps" -> result.success(apps())
                        "installedPackages" -> result.success(installedPackages())
                        "appIcon" -> result.success(appIcon(call.argument<String>("package") ?: ""))
                        "openAppStorage" -> {
                            openAppStorage(call.argument<String>("package") ?: ""); result.success(true)
                        }
                        "clearAllCaches" -> result.success(clearAllCaches())
                        "rescanPaths" -> {
                            rescan(call.argument<List<String>>("paths") ?: emptyList()); result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("native_error", e.message, null)
                }
            }
    }

    // Volume ──────────────────────────────────────────────────────────────
    //
    // StorageStatsManager reports the advertised capacity, which is the number
    // Settings shows and therefore the number worth agreeing with. StatFs
    // reports the formatted capacity, several GB smaller, which makes the app
    // look wrong sitting next to Settings. Prefer the first, keep the second
    // as the fallback.
    private fun volume(): Map<String, Any> {
        val stat = StatFs(Environment.getDataDirectory().path)
        var total = stat.blockCountLong * stat.blockSizeLong
        var free = stat.availableBlocksLong * stat.blockSizeLong
        try {
            val ssm = getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
            total = ssm.getTotalBytes(StorageManager.UUID_DEFAULT)
            free = ssm.getFreeBytes(StorageManager.UUID_DEFAULT)
        } catch (_: Throwable) {
            // Keep the StatFs numbers.
        }
        return mapOf("total" to total, "free" to free, "used" to (total - free))
    }

    // Permissions ─────────────────────────────────────────────────────────
    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }

    private fun openAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // The per-app page when the OEM honours it, otherwise the whole list.
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:" + packageName)
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return
            } catch (_: Throwable) {
                // Fall through to the list.
            }
            open(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
        } else {
            openAppStorage(packageName)
        }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun open(action: String) {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // Per-app sizes ───────────────────────────────────────────────────────
    //
    // queryStatsForPackage is the source Settings itself reads, so the totals
    // agree to the byte. It throws for a handful of packages (odd storage
    // UUIDs, work profiles), so every package is wrapped individually: one bad
    // package must not empty the whole list.
    private fun apps(): List<Map<String, Any>> {
        val pm = packageManager
        val ssm = try {
            getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
        } catch (_: Throwable) {
            null
        }
        val user = Process.myUserHandle()
        val out = ArrayList<Map<String, Any>>()

        for (app in pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
            var appBytes = 0L
            var dataBytes = 0L
            var cacheBytes = 0L
            var measured = false
            if (ssm != null) {
                try {
                    val uuid = app.storageUuid
                    val s = ssm.queryStatsForPackage(uuid, app.packageName, user)
                    appBytes = s.appBytes
                    dataBytes = s.dataBytes
                    cacheBytes = s.cacheBytes
                    measured = true
                } catch (_: Throwable) {
                    measured = false
                }
            }
            if (!measured) {
                // No usage access. The APK on disk is all that can be seen.
                appBytes = try {
                    File(app.sourceDir).length()
                } catch (_: Throwable) {
                    0L
                }
            }
            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            out.add(
                mapOf(
                    "package" to app.packageName,
                    "label" to pm.getApplicationLabel(app).toString(),
                    "app" to appBytes,
                    // dataBytes already includes cacheBytes; keep them separable.
                    "data" to (dataBytes - cacheBytes).coerceAtLeast(0L),
                    "cache" to cacheBytes,
                    "total" to (appBytes + dataBytes),
                    "system" to isSystem,
                    "measured" to measured
                )
            )
        }
        return out
    }

    private fun installedPackages(): List<String> =
        packageManager.getInstalledApplications(0).map { it.packageName }

    private fun appIcon(pkg: String): ByteArray? {
        if (pkg.isEmpty()) return null
        return try {
            val d: Drawable = packageManager.getApplicationIcon(pkg)
            val bmp = if (d is BitmapDrawable && d.bitmap != null) {
                Bitmap.createScaledBitmap(d.bitmap, 96, 96, true)
            } else {
                val b = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val c = Canvas(b)
                d.setBounds(0, 0, c.width, c.height)
                d.draw(c)
                b
            }
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    // Hand-offs ───────────────────────────────────────────────────────────
    //
    // No app can clear another app cache on Android 11 and up. These two are
    // the whole of what is possible: jump to the app own storage page, or ask
    // the system to run its own clear-all-caches prompt.
    private fun openAppStorage(pkg: String) {
        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:" + pkg))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
    }

    private fun clearAllCaches(): Boolean {
        return try {
            startActivity(
                Intent(StorageManager.ACTION_CLEAR_APP_CACHE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Tell MediaStore the files are gone. Without this a deleted photo keeps
     * its row and goes on showing as a grey tile in Photos and Files until
     * something else happens to trigger a scan.
     */
    private fun rescan(paths: List<String>) {
        if (paths.isEmpty()) return
        MediaScannerConnection.scanFile(applicationContext, paths.toTypedArray(), null, null)
    }
}
