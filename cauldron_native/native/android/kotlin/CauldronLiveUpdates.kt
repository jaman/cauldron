package cauldron.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import org.json.JSONObject

/**
 * `CauldronNative.LiveActivity` on Android: a Live Update, an ongoing notification the
 * system promotes to the status bar chip and the top of the shade, drawn with
 * `Notification.ProgressStyle` on Android 16 and a plain progress bar before it.
 */
object CauldronLiveUpdates {
    private const val CHANNEL = "cauldron_live"
    private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"
    private const val PROMOTED = "android.requestPromotedOngoing"

    fun start(context: Context, activity: CauldronActivity?, request: JSONObject) {
        val id = request.getString("id")
        if (context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) return started(context, request)
        if (activity == null) return CauldronDevice.answer(id, "error", "unavailable")
        CauldronDevice.launch(activity, ActivityResultContracts.RequestPermission(), PERMISSION) { granted ->
            if (granted) started(context, request) else CauldronDevice.answer(id, "error", "unavailable")
        }
    }

    fun update(context: Context, request: JSONObject) {
        if (showing(context, request.getString("id"))) post(context, request, ongoing = true)
    }

    fun finish(context: Context, request: JSONObject) {
        if (showing(context, request.getString("id"))) post(context, request, ongoing = false)
    }

    private fun started(context: Context, request: JSONObject) {
        post(context, request, ongoing = true)
        CauldronDevice.answer(request.getString("id"), "ok", "started")
    }

    private fun showing(context: Context, id: String): Boolean =
        context.getSystemService(NotificationManager::class.java).activeNotifications.any { it.tag == id && it.notification.channelId == CHANNEL }

    private fun post(context: Context, request: JSONObject, ongoing: Boolean) {
        channel(context)
        val id = request.getString("id")
        val title = request.optString("title")
        val detail = request.optString("detail")
        val progress = if (request.isNull("progress")) null else request.optDouble("progress").coerceIn(0.0, 1.0)
        val icon = Icon.createWithBitmap(CauldronIcons.bitmap(null, request.optString("android_icon", "Bolt"), 96))
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(detail)
            .setContentIntent(opening(context, id, request.optString("url").ifEmpty { null }))
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
        countdown(builder, request, ongoing)
        request.optString("image").ifEmpty { null }?.let { image ->
            val picture = CauldronAssets.drawable(context, image)
            if (picture != 0) builder.setLargeIcon(Icon.createWithResource(context, picture))
        }
        if (Build.VERSION.SDK_INT >= 36) promoted(builder, icon, detail, progress, ongoing)
        else if (progress != null) builder.setProgress(100, (progress * 100).toInt(), false)
        context.getSystemService(NotificationManager::class.java).notify(id, 0, builder.build())
    }

    private fun promoted(builder: Notification.Builder, icon: Icon, detail: String, progress: Double?, ongoing: Boolean) {
        val style = Notification.ProgressStyle().setProgressTrackerIcon(icon).setStyledByProgress(true)
        if (progress == null) style.setProgressIndeterminate(ongoing) else style.setProgress((progress * 100).toInt())
        builder.setStyle(style).setShortCriticalText(detail)
        if (ongoing) builder.extras.putBoolean(PROMOTED, true)
    }

    private fun countdown(builder: Notification.Builder, request: JSONObject, ongoing: Boolean) {
        if (request.isNull("ends_at") || !ongoing) return
        val ends = (request.optDouble("ends_at") * 1000).toLong()
        builder.setWhen(ends).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
        request.optString("ends_label").ifEmpty { null }?.let { builder.setSubText(it) }
    }

    private fun opening(context: Context, id: String, url: String?): PendingIntent {
        val intent = (if (url != null) Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).setPackage(context.packageName) else Intent(context, CauldronActivity::class.java))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun channel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) != null) return
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "$label (live)", NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null) }
        )
    }
}
