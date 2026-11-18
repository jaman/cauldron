package foodtruck

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.LocationCity
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode
import kotlin.math.min
import kotlin.math.roundToInt

object OrderTilesView : CauldronNativeView {
    override val name = "order_tiles"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val orders = (node.props["orders"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
        val shape = RoundedCornerShape(10.dp)
        HeroTiling(Modifier.fillMaxWidth().heightIn(max = 250.dp)) {
            for (order in orders) {
                key(order["number"]) {
                    val donuts = (order["donuts"] as? List<*>).orEmpty().map { donut -> (donut as? List<*>)?.map { it.toString() }.orEmpty() }
                    DonutStack(
                        donuts,
                        Modifier.background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), shape)
                            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, shape)
                            .padding(6.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun HeroTiling(modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val spacing = 10.dp.roundToPx()
        val width = constraints.maxWidth
        val height = if (constraints.maxHeight == Constraints.Infinity) width / 2 else constraints.maxHeight
        val hero = min((width - spacing) / 2, height)
        val tile = (hero - spacing) / 2
        val total = hero * 2 + spacing
        val left = (width - total) / 2
        val placeables = measurables.mapIndexed { index, measurable ->
            val side = if (index == 0) hero else tile
            measurable.measure(Constraints.fixed(side, side))
        }
        layout(width, hero) {
            placeables.forEachIndexed { index, placeable ->
                if (index == 0) {
                    placeable.place(left, 0)
                } else {
                    val column = (index - 1) % 2
                    val row = if (index - 1 < 2) 0 else 1
                    val x = left + hero + spacing + if (column == 0) 0 else hero - tile
                    val y = if (row == 0) 0 else hero - tile
                    placeable.place(x, y)
                }
            }
        }
    }
}

object DonutLatticeView : CauldronNativeView {
    override val name = "donut_lattice"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val donuts = node.layerLists("donuts").take(14)
        Layout({ for (layers in donuts) DonutLayers(layers) }, Modifier.fillMaxSize().heightIn(min = 180.dp)) { measurables, constraints ->
            val columns = 5
            val rows = 3
            val spacing = 10.dp.roundToPx()
            val width = constraints.maxWidth
            val height = if (constraints.maxHeight == Constraints.Infinity) width * rows / columns else constraints.maxHeight
            val cell = min(width / columns, height / rows)
            val usedWidth = cell * columns
            val usedHeight = cell * rows
            val originX = width - usedWidth
            val originY = height - usedHeight
            val side = (cell - spacing).coerceAtLeast(1)
            val placeables = measurables.map { it.measure(Constraints.fixed(side, side)) }
            layout(width, height) {
                var index = 0
                for (row in 0 until rows) {
                    val even = row % 2 == 0
                    for (column in 0 until if (even) columns else columns - 1) {
                        if (index >= placeables.size) break
                        val x = originX + cell * column + (if (even) 0 else cell / 2) + spacing / 2
                        placeables[index].place(x, originY + cell * row + spacing / 2)
                        index++
                    }
                }
            }
        }
    }
}

object TagFlowView : CauldronNativeView {
    override val name = "tag_flow"

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val tags = (node.props["tags"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
        val leading = node.string("alignment") == "leading"
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp, if (leading) Alignment.Start else Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            for (tag in tags) Tag(tag)
        }
    }

    @Composable
    private fun Tag(tag: Map<*, *>) {
        Row(
            Modifier.background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), RoundedCornerShape(5.dp)).padding(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(14.dp), contentAlignment = Alignment.Center) {
                when (tag["kind"]) {
                    "donut" -> DonutLayers((tag["layers"] as? List<*>).orEmpty().map { it.toString() }, Modifier.size(20.dp))
                    "city" -> Icon(Icons.Outlined.LocationCity, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    else -> Icon(Icons.Outlined.LocalOffer, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.width(6.dp))
            Text(tag["title"]?.toString() ?: "", fontSize = 12.sp)
        }
    }
}
