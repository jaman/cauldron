package cauldron.app

import android.content.Context

object CauldronPurchases {
    fun products(context: Context, id: String, keys: List<String>) = CauldronDevice.answer(id, "error", "not_configured")

    fun buy(context: Context, activity: CauldronActivity?, id: String, key: String) = CauldronDevice.answer(id, "error", "not_configured")

    fun owned(context: Context, id: String) = CauldronDevice.answer(id, "error", "not_configured")

    fun watch(context: Context, id: String) = Unit

    fun subscription(context: Context, id: String, keys: List<String>) = CauldronDevice.answer(id, "error", "not_configured")

    fun transactions(context: Context, id: String) = CauldronDevice.answer(id, "error", "not_configured")

    fun manage(context: Context) = Unit

    fun redeem(context: Context, id: String) = CauldronDevice.answer(id, "error", "not_configured")
}
