package cauldron.app

import android.content.Context
import android.content.Intent
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

object CauldronPush {
    private const val PREFERENCES = "cauldron"
    private const val KEY = "push"

    fun register(activity: CauldronActivity, id: String) {
        activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putString(KEY, id).apply()
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) CauldronDevice.answer(id, "ok", token(task.result)) else CauldronDevice.answer(id, "error", "unavailable")
        }
    }

    fun renewed(context: Context, token: String) {
        id(context)?.let { CauldronDevice.answer(it, "ok", token(token)) }
    }

    fun received(context: Context, message: RemoteMessage) {
        val id = id(context) ?: return
        CauldronDevice.answer(id, "ok", JSONObject().put("received", JSONObject(message.data as Map<*, *>)))
        val shown = message.notification ?: return
        CauldronNotifications.post(
            context,
            message.messageId ?: id,
            shown.title ?: "",
            shown.body ?: "",
            true,
            message.data + ("google.message_id" to (message.messageId ?: ""))
        )
    }

    fun opened(context: Context, intent: Intent?): Boolean {
        val extras = intent?.extras ?: return false
        if (!extras.containsKey("google.message_id")) return false
        val id = id(context) ?: return false
        val data = JSONObject()
        for (key in extras.keySet()) {
            if (key.startsWith("google.") || key.startsWith("gcm.") || key == "from" || key == "collapse_key") continue
            extras.getString(key)?.let { data.put(key, it) }
        }
        intent.removeExtra("google.message_id")
        CauldronDevice.answer(id, "ok", JSONObject().put("opened", data))
        return true
    }

    private fun id(context: Context): String? =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY, null)

    private fun token(token: String) = JSONObject().put("token", token).put("service", "fcm")
}

class CauldronMessaging : FirebaseMessagingService() {
    override fun onNewToken(token: String) = CauldronPush.renewed(this, token)

    override fun onMessageReceived(message: RemoteMessage) = CauldronPush.received(this, message)
}
