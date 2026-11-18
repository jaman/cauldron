package cauldron.app

import android.content.pm.PackageManager
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.CameraMoveStartedReason
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapType
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState
import kotlin.math.cos
import kotlin.math.log2
import kotlin.math.pow

private const val EARTH = 40_075_016.686

@Composable
internal fun NodeMap(node: UiNode, modifier: Modifier) {
    val context = LocalContext.current
    val widthDp = LocalConfiguration.current.screenWidthDp.toDouble()
    val camera = rememberCameraPositionState()
    val center = node.props["center"] as? List<*>
    val latitude = (center?.getOrNull(0) as? Number)?.toDouble()
    val longitude = (center?.getOrNull(1) as? Number)?.toDouble()
    val distance = node.double("distance") ?: 1000.0
    val events = remember(node.id) { UiEvents(node.id) }

    LaunchedEffect(latitude, longitude, distance) {
        if (latitude != null && longitude != null) {
            camera.position = CameraPosition.fromLatLngZoom(LatLng(latitude, longitude), zoom(latitude, distance, widthDp))
        }
    }

    LaunchedEffect(camera.isMoving) {
        if (camera.isMoving || camera.cameraMoveStartedReason != CameraMoveStartedReason.GESTURE || "move" !in node.events) return@LaunchedEffect
        val target = camera.position.target
        events.send(
            "move",
            org.json.JSONObject()
                .put("latitude", target.latitude)
                .put("longitude", target.longitude)
                .put("distance", metres(target.latitude, camera.position.zoom.toDouble(), widthDp))
        )
    }

    val located = node.bool("user_location") &&
        context.checkSelfPermission("android.permission.ACCESS_FINE_LOCATION") == PackageManager.PERMISSION_GRANTED
    GoogleMap(
        modifier = if (hasFrameHeight(node)) modifier else modifier.height(300.dp),
        cameraPositionState = camera,
        properties = MapProperties(mapType = mapType(node.string("style")), isMyLocationEnabled = located),
        uiSettings = MapUiSettings(myLocationButtonEnabled = located, zoomControlsEnabled = false)
    ) {
        markers(node).forEachIndexed { index, marker ->
            Marker(
                state = rememberUpdatedMarkerState(position = marker.position),
                title = marker.title,
                icon = BitmapDescriptorFactory.defaultMarker(marker.hue),
                onClick = {
                    events.send("select", index)
                    false
                }
            )
        }
    }
}

private class MapMarker(val title: String, val position: LatLng, val hue: Float)

@Suppress("UNCHECKED_CAST")
private fun markers(node: UiNode): List<MapMarker> = (node.props["markers"] as? List<Map<String, Any?>> ?: emptyList()).mapNotNull { raw ->
    val latitude = (raw["latitude"] as? Number)?.toDouble() ?: return@mapNotNull null
    val longitude = (raw["longitude"] as? Number)?.toDouble() ?: return@mapNotNull null
    MapMarker(raw["title"] as? String ?: "", LatLng(latitude, longitude), hue(raw["colour"] as? String))
}

private fun hue(colour: String?): Float {
    val color = colour?.let(::hexColor) ?: return BitmapDescriptorFactory.HUE_RED
    val hsv = FloatArray(3)
    android.graphics.Color.RGBToHSV((color.red * 255).toInt(), (color.green * 255).toInt(), (color.blue * 255).toInt(), hsv)
    return hsv[0]
}

private fun mapType(style: String?): MapType = when (style) {
    "satellite" -> MapType.SATELLITE
    "hybrid" -> MapType.HYBRID
    else -> MapType.NORMAL
}

private fun zoom(latitude: Double, distance: Double, widthDp: Double): Float =
    log2(EARTH * cos(Math.toRadians(latitude)) * widthDp / 256.0 / distance).toFloat().coerceIn(2f, 21f)

private fun metres(latitude: Double, zoom: Double, widthDp: Double): Double =
    EARTH * cos(Math.toRadians(latitude)) * widthDp / 256.0 / 2.0.pow(zoom)

/**
 * A map an app's own view places, looking at `latitude`, `longitude` from `distance`
 * metres away, tilted `tilt` degrees and turned to `bearing`, with the user's gestures
 * off; it follows each change of the camera's values.
 */
@Composable
fun CauldronMapView(latitude: Double, longitude: Double, distance: Double, tilt: Float, bearing: Float, modifier: Modifier = Modifier) {
    val widthDp = LocalConfiguration.current.screenWidthDp.toDouble()
    val camera = rememberCameraPositionState()
    LaunchedEffect(latitude, longitude, distance, tilt, bearing) {
        camera.position = CameraPosition(LatLng(latitude, longitude), zoom(latitude, distance, widthDp), tilt.coerceIn(0f, 67.5f), bearing)
    }
    GoogleMap(
        modifier = modifier,
        cameraPositionState = camera,
        properties = MapProperties(isBuildingEnabled = true),
        uiSettings = MapUiSettings(
            zoomControlsEnabled = false,
            scrollGesturesEnabled = false,
            zoomGesturesEnabled = false,
            tiltGesturesEnabled = false,
            rotationGesturesEnabled = false,
            compassEnabled = false,
            mapToolbarEnabled = false
        )
    )
}
