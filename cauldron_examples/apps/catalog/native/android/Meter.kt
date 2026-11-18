package catalog

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode

object Meter : CauldronNativeView {
    override val name = "meter"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val value = (node.double("value") ?: 0.0).toFloat().coerceIn(0f, 1f)
        val track = MaterialTheme.colorScheme.surfaceVariant
        val fill = MaterialTheme.colorScheme.primary
        Box(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(96.dp)) {
                drawArc(track, 135f, 270f, false, style = Stroke(12.dp.toPx(), cap = StrokeCap.Round))
                drawArc(fill, 135f, 270f * value, false, style = Stroke(12.dp.toPx(), cap = StrokeCap.Round))
            }
            Text("${(value * 100).toInt()}", style = MaterialTheme.typography.titleLarge)
        }
    }
}
