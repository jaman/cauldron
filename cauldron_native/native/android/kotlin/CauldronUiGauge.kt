package cauldron.app

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

@Composable
internal fun NodeGauge(node: UiNode, modifier: Modifier) {
    val low = node.double("min") ?: 0.0
    val high = maxOf(node.double("max") ?: 1.0, low + 0.0001)
    val value = (node.double("value") ?: 0.0).coerceIn(low, high)
    val share = ((value - low) / (high - low)).toFloat()
    val title = node.string("title")
    when (node.string("style")) {
        "circular" -> Box(modifier.size(56.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(progress = { share }, modifier = Modifier.fillMaxSize())
            GaugeCurrent(node, Modifier.padding(12.dp))
        }
        "segmented" -> Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            title?.let { Text(it) }
            Row(Modifier.fillMaxWidth().height(11.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                for (index in 0 until maxOf(high.toInt(), 1)) {
                    Box(
                        Modifier.weight(1f).fillMaxSize().alpha(if (index < value) 1f else 0.35f)
                            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
                    )
                }
            }
        }
        else -> Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            title?.let { Text(it) }
            LinearProgressIndicator(progress = { share }, modifier = Modifier.fillMaxWidth())
            GaugeCurrent(node, Modifier.size(24.dp).align(Alignment.CenterHorizontally))
        }
    }
}

@Composable
private fun GaugeCurrent(node: UiNode, modifier: Modifier) {
    val images = (node.props["image"] as? List<*>)?.map { it.toString() }
    if (images != null) {
        Box(modifier) {
            for (image in images) {
                val id = cauldronAsset(image)
                if (id != 0) Image(painterResource(id), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            }
        }
    } else {
        node.string("current")?.let { Text(it, modifier = modifier) }
    }
}
