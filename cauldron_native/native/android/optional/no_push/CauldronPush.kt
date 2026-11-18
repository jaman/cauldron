package cauldron.app

import android.content.Context
import android.content.Intent

object CauldronPush {
    fun register(activity: CauldronActivity, id: String) = CauldronDevice.answer(id, "error", "not_configured")

    fun opened(context: Context, intent: Intent?): Boolean = false
}
