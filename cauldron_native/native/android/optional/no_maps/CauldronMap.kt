package cauldron.app

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
internal fun NodeMap(node: UiNode, modifier: Modifier) {
    Text(
        "A map needs the app's Google Maps key: maps: [android_key: …] in its :cauldron_native config",
        color = MaterialTheme.colorScheme.error,
        modifier = modifier
    )
}

/** The notice an app's own map shows when the app has no Google Maps key. */
@Composable
fun CauldronMapView(latitude: Double, longitude: Double, distance: Double, tilt: Float, bearing: Float, modifier: Modifier = Modifier) {
    Text(
        "A map needs the app's Google Maps key: maps: [android_key: …] in its :cauldron_native config",
        color = MaterialTheme.colorScheme.error,
        modifier = modifier
    )
}
