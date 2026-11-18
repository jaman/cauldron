package cauldron.app

import android.content.Context
import android.content.pm.PackageManager
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClient.BillingResponseCode
import com.android.billingclient.api.BillingClient.ProductType
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import org.json.JSONArray
import org.json.JSONObject

/**
 * `CauldronNative.Purchases` on Android, with Google Play Billing. The products' types
 * come from the app's manifest (`cauldron.purchases`, written from its config); a
 * product's Play id is the app's id, a dot and its key.
 */
object CauldronPurchases {
    private var client: BillingClient? = null
    private var buying: String? = null
    private val watchers = mutableListOf<String>()
    private var types: Map<String, String> = emptyMap()

    fun products(context: Context, id: String, keys: List<String>) = connected(context, id) { billing ->
        details(context, billing, keys) { found ->
            CauldronDevice.answer(id, "ok", JSONObject().put("products", JSONArray(found.map(::described))))
        }
    }

    fun buy(context: Context, activity: CauldronActivity?, id: String, key: String) = connected(context, id) { billing ->
        if (activity == null) return@connected CauldronDevice.answer(id, "error", "unavailable")
        details(context, billing, listOf(key)) { found ->
            val product = found.firstOrNull() ?: return@details CauldronDevice.answer(id, "error", "not_found")
            val offer = product.subscriptionOfferDetails?.firstOrNull()?.offerToken
            val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
            if (offer != null) params.setOfferToken(offer)
            buying = id
            val started = billing.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params.build())).build())
            if (started.responseCode != BillingResponseCode.OK) finishBuying(error(started))
        }
    }

    fun owned(context: Context, id: String) = connected(context, id) { billing ->
        entitled(context, billing) { keys -> CauldronDevice.answer(id, "ok", JSONObject().put("owned", JSONArray(keys))) }
    }

    fun watch(context: Context, id: String) {
        watchers.add(id)
        connected(context, id) {}
    }

    fun subscription(context: Context, id: String, keys: List<String>) = connected(context, id) { billing ->
        billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(ProductType.SUBS).build()) { _, purchases ->
            val current = purchases.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED && it.products.any { product -> key(context, product) in keys } }
            val key = current?.products?.map { key(context, it) }?.firstOrNull { it in keys }
            val found = JSONObject()
            if (key != null) {
                found.put("current", key)
                if (current.isAutoRenewing) found.put("next", key)
            }
            CauldronDevice.onMain { CauldronDevice.answer(id, "ok", JSONObject().put("subscription", found)) }
        }
    }

    fun transactions(context: Context, id: String) = connected(context, id) { billing ->
        val found = mutableListOf<Pair<Purchase, Boolean>>()
        var waiting = 2
        for (type in listOf(ProductType.INAPP, ProductType.SUBS)) {
            billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build()) { _, purchases ->
                purchases.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }.forEach { found.add(it to (type == ProductType.SUBS)) }
                waiting -= 1
                if (waiting == 0) CauldronDevice.onMain {
                    val recent = found.sortedByDescending { it.first.purchaseTime }.take(10).map { (purchase, subscription) ->
                        JSONObject()
                            .put("id", purchase.orderId ?: purchase.purchaseToken)
                            .put("key", key(context, purchase.products.first()))
                            .put("purchased", purchase.purchaseTime / 1000.0)
                            .put("subscription", subscription)
                    }
                    CauldronDevice.answer(id, "ok", JSONObject().put("transactions", JSONArray(recent)))
                }
            }
        }
    }

    fun manage(context: Context) = open(context, "https://play.google.com/store/account/subscriptions?package=${context.packageName}")

    fun redeem(context: Context, id: String) {
        open(context, "https://play.google.com/redeem")
        CauldronDevice.answer(id, "ok", "finished")
    }

    private fun open(context: Context, url: String) {
        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }

    private fun connected(context: Context, id: String, then: (BillingClient) -> Unit) {
        client?.takeIf { it.isReady }?.let { return then(it) }
        types = declared(context)
        val billing = BillingClient.newBuilder(context.applicationContext)
            .setListener { result, purchases -> updated(context.applicationContext, result, purchases) }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        client = billing
        billing.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingResponseCode.OK) then(billing) else CauldronDevice.answer(id, "error", "unavailable")
            }

            override fun onBillingServiceDisconnected() {
                client = null
            }
        })
    }

    private fun updated(context: Context, result: BillingResult, purchases: List<Purchase>?) {
        when (result.responseCode) {
            BillingResponseCode.OK -> purchases.orEmpty().forEach { settle(context, it) }
            BillingResponseCode.USER_CANCELED -> finishBuying("cancelled" to null)
            BillingResponseCode.ITEM_ALREADY_OWNED -> finishBuying("ok" to "purchased")
            else -> finishBuying(error(result))
        }
        client?.let { billing -> entitled(context, billing) { keys -> watchers.forEach { CauldronDevice.answer(it, "ok", JSONObject().put("owned", JSONArray(keys))) } } }
    }

    private fun settle(context: Context, purchase: Purchase) {
        val billing = client ?: return
        if (purchase.purchaseState == Purchase.PurchaseState.PENDING) return finishBuying("ok" to "pending")
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        val consumable = purchase.products.any { types[key(context, it)] == "consumable" }
        if (consumable) {
            billing.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()) { result, _ ->
                finishBuying(if (result.responseCode == BillingResponseCode.OK) "ok" to "purchased" else error(result))
            }
        } else if (!purchase.isAcknowledged) {
            billing.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()) { result ->
                finishBuying(if (result.responseCode == BillingResponseCode.OK) "ok" to "purchased" else error(result))
            }
        } else {
            finishBuying("ok" to "purchased")
        }
    }

    private fun finishBuying(answer: Pair<String, String?>) {
        val id = buying ?: return
        buying = null
        CauldronDevice.answer(id, answer.first, answer.second)
    }

    private fun details(context: Context, billing: BillingClient, keys: List<String>, then: (List<ProductDetails>) -> Unit) {
        val byType = keys.groupBy { if (types[it] == "subscription") ProductType.SUBS else ProductType.INAPP }
        val found = mutableListOf<ProductDetails>()
        var waiting = byType.size
        if (waiting == 0) return then(found)
        byType.forEach { (type, typed) ->
            val products = typed.map { QueryProductDetailsParams.Product.newBuilder().setProductId(storeId(context, it)).setProductType(type).build() }
            billing.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(products).build()) { result, details ->
                if (result.responseCode == BillingResponseCode.OK) found.addAll(details.productDetailsList)
                waiting -= 1
                if (waiting == 0) CauldronDevice.onMain { then(found) }
            }
        }
    }

    private fun entitled(context: Context, billing: BillingClient, then: (List<String>) -> Unit) {
        val keys = mutableListOf<String>()
        var waiting = 2
        for (type in listOf(ProductType.INAPP, ProductType.SUBS)) {
            billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build()) { _, purchases ->
                purchases.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                    .flatMap { it.products }
                    .map { key(context, it) }
                    .filter { types[it] != "consumable" }
                    .let(keys::addAll)
                waiting -= 1
                if (waiting == 0) CauldronDevice.onMain { then(keys) }
            }
        }
    }

    private fun described(product: ProductDetails): JSONObject {
        val price = product.oneTimePurchaseOfferDetails?.formattedPrice
            ?: product.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
            ?: ""
        val key = product.productId.substringAfterLast('.')
        val described = JSONObject()
            .put("key", key)
            .put("name", product.name)
            .put("description", product.description)
            .put("price", price)
            .put("type", types[key] ?: "non_consumable")
        product.oneTimePurchaseOfferDetails?.let { described.put("amount", it.priceAmountMicros / 1_000_000.0) }
        val offers = product.subscriptionOfferDetails.orEmpty()
        val base = offers.firstOrNull { it.offerId == null } ?: offers.firstOrNull()
        val phase = base?.pricingPhases?.pricingPhaseList?.lastOrNull()
        if (phase != null) {
            val amount = phase.priceAmountMicros / 1_000_000.0
            described.put("amount", amount)
            period(phase.billingPeriod)?.let { (unit, count) ->
                described.put("period", JSONObject().put("unit", unit).put("count", count))
                val months = when (unit) { "year" -> count * 12; "month" -> count; else -> 0 }
                if (months > 1) {
                    val format = java.text.NumberFormat.getCurrencyInstance().apply { currency = java.util.Currency.getInstance(phase.priceCurrencyCode) }
                    described.put("price_per_month", format.format(amount / months))
                }
            }
            described.put("intro_eligible", offers.any { it.pricingPhases.pricingPhaseList.size > 1 })
        }
        return described
    }

    private fun period(iso: String): Pair<String, Int>? {
        val match = Regex("^P(\\d+)([DWMY])$").find(iso) ?: return null
        val unit = when (match.groupValues[2]) { "D" -> "day"; "W" -> "week"; "M" -> "month"; else -> "year" }
        return unit to match.groupValues[1].toInt()
    }

    private fun error(result: BillingResult): Pair<String, String> = "error" to when (result.responseCode) {
        BillingResponseCode.ITEM_UNAVAILABLE -> "not_found"
        BillingResponseCode.BILLING_UNAVAILABLE, BillingResponseCode.SERVICE_UNAVAILABLE, BillingResponseCode.SERVICE_DISCONNECTED -> "unavailable"
        else -> "failed"
    }

    private fun storeId(context: Context, key: String) = context.packageName + "." + key

    private fun key(context: Context, productId: String) = productId.removePrefix(context.packageName + ".")

    private fun declared(context: Context): Map<String, String> {
        val info = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        val json = JSONObject(info.metaData?.getString("cauldron.purchases") ?: "{}")
        return json.keys().asSequence().associateWith { json.getString(it) }
    }
}
