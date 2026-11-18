package cauldron.app

import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import androidx.activity.result.contract.ActivityResultContracts
import org.json.JSONObject

object CauldronLocation {
    private val permissions = arrayOf("android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION")
    private var watching: LocationListener? = null

    fun current(activity: CauldronActivity, request: JSONObject) {
        val id = request.getString("id")
        val precise = request.optBoolean("precise", true)
        allowed(activity, id) {
            val manager = activity.getSystemService(LocationManager::class.java)
            val provider = provider(manager, precise) ?: return@allowed CauldronDevice.answer(id, "error", "unavailable")
            manager.getCurrentLocation(provider, null, activity.mainExecutor) { location ->
                val found = location ?: lastKnown(manager)
                if (found == null) CauldronDevice.answer(id, "error", "unavailable") else CauldronDevice.answer(id, "ok", reading(found))
            }
        }
    }

    fun watch(activity: CauldronActivity, request: JSONObject) {
        val id = request.getString("id")
        val precise = request.optBoolean("precise", true)
        val distance = request.optDouble("distance", 10.0).toFloat()
        allowed(activity, id) {
            stop(activity)
            val manager = activity.getSystemService(LocationManager::class.java)
            val provider = provider(manager, precise) ?: return@allowed CauldronDevice.answer(id, "error", "unavailable")
            val listener = LocationListener { location -> CauldronDevice.answer(id, "ok", reading(location)) }
            manager.requestLocationUpdates(provider, 1000L, distance, listener, Looper.getMainLooper())
            watching = listener
        }
    }

    fun stop(activity: CauldronActivity) {
        val listener = watching ?: return
        activity.getSystemService(LocationManager::class.java).removeUpdates(listener)
        watching = null
    }

    private fun allowed(activity: CauldronActivity, id: String, then: () -> Unit) {
        if (!CauldronDevice.declared(activity, "location")) return CauldronDevice.answer(id, "error", "not_declared")
        if (granted(activity)) return then()
        CauldronDevice.launch(activity, ActivityResultContracts.RequestMultiplePermissions(), permissions) { result ->
            if (result.values.any { it }) then() else CauldronDevice.answer(id, "error", "denied")
        }
    }

    private fun granted(activity: CauldronActivity): Boolean =
        permissions.any { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun provider(manager: LocationManager, precise: Boolean): String? = when {
        manager.hasProvider(LocationManager.FUSED_PROVIDER) && manager.isProviderEnabled(LocationManager.FUSED_PROVIDER) -> LocationManager.FUSED_PROVIDER
        precise && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
        manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
        manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
        else -> null
    }

    private fun lastKnown(manager: LocationManager): Location? =
        manager.getProviders(true).mapNotNull { manager.getLastKnownLocation(it) }.maxByOrNull { it.elapsedRealtimeNanos }

    private fun reading(location: Location): JSONObject {
        val reading = JSONObject()
            .put("latitude", location.latitude)
            .put("longitude", location.longitude)
            .put("accuracy", if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0)
            .put("time", location.time)
        if (location.hasAltitude()) reading.put("altitude", location.altitude)
        if (location.hasSpeed()) reading.put("speed", location.speed.toDouble())
        if (location.hasBearing()) reading.put("heading", location.bearing.toDouble())
        return reading
    }
}
