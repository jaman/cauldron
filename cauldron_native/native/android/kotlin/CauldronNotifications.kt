package cauldron.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object CauldronNotifications {
    private const val SOUND = "cauldron"
    private const val QUIET = "cauldron_quiet"
    private const val EXTRA = "cauldron_notification"
    private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"

    fun schedule(context: Context, activity: CauldronActivity?, request: JSONObject) {
        val id = request.getString("id")
        if (!CauldronDevice.declared(context, "notifications")) return CauldronDevice.answer(id, "error", "not_declared")
        if (context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) return enqueue(context, request)
        if (activity == null) return CauldronDevice.answer(id, "error", "denied")
        CauldronDevice.launch(activity, ActivityResultContracts.RequestPermission(), PERMISSION) { granted ->
            if (granted) enqueue(context, request) else CauldronDevice.answer(id, "error", "denied")
        }
    }

    fun cancel(context: Context, id: String) {
        WorkManager.getInstance(context).cancelUniqueWork(work(id))
        context.getSystemService(NotificationManager::class.java).cancel(id, 0)
    }

    fun opened(intent: Intent?) {
        val id = intent?.getStringExtra(EXTRA) ?: return
        intent.removeExtra(EXTRA)
        CauldronDevice.answer(id, "ok", "opened")
    }

    fun post(context: Context, id: String, title: String, body: String, sound: Boolean, extras: Map<String, String> = emptyMap()) {
        channels(context)
        val intent = Intent(context, CauldronActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (extras.isEmpty()) intent.putExtra(EXTRA, id) else extras.forEach { (key, value) -> intent.putExtra(key, value) }
        val pending = PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, if (sound) SOUND else QUIET)
            .setSmallIcon(R.drawable.cauldron_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(id, 0, notification)
    }

    private fun enqueue(context: Context, request: JSONObject) {
        val id = request.getString("id")
        val delay = (request.optDouble("after", 0.0) * 1000).toLong()
        val data = workDataOf(
            "id" to id,
            "title" to request.optString("title"),
            "body" to request.optString("body"),
            "sound" to request.optBoolean("sound", true)
        )
        val job = OneTimeWorkRequestBuilder<CauldronNotifyWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(work(id), ExistingWorkPolicy.REPLACE, job)
        CauldronDevice.answer(id, "ok", "scheduled")
    }

    private fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(SOUND) != null) return
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        manager.createNotificationChannel(NotificationChannel(SOUND, label, NotificationManager.IMPORTANCE_HIGH))
        manager.createNotificationChannel(
            NotificationChannel(QUIET, "$label (silent)", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) }
        )
    }

    private fun work(id: String) = "cauldron-notification-$id"
}

class CauldronNotifyWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        val data = inputData
        CauldronNotifications.post(
            applicationContext,
            data.getString("id") ?: return Result.failure(),
            data.getString("title") ?: "",
            data.getString("body") ?: "",
            data.getBoolean("sound", true)
        )
        return Result.success()
    }
}
