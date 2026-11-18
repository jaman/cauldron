package notes

import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode

object Rating : CauldronNativeView {
    override val name = "rating"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val value = node.double("value")?.toInt() ?: 0
        Row {
            for (star in 1..5) {
                IconButton(onClick = { events.send("change", if (star == value) 0 else star) }) {
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = if (star == 1) "1 star" else "$star stars",
                        tint = if (star <= value) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
                    )
                }
            }
        }
    }
}
