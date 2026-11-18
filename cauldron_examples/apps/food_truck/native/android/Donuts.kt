package foodtruck

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode
import cauldron.app.cauldronAsset
import cauldron.app.cauldronAssetColour
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt

internal fun UiNode.strings(key: String): List<String> = (props[key] as? List<*>)?.map { it.toString() }.orEmpty()

internal fun UiNode.layerLists(key: String): List<List<String>> =
    (props[key] as? List<*>)?.map { donut -> (donut as? List<*>)?.map { it.toString() }.orEmpty() }.orEmpty()

@Composable
fun DonutLayers(layers: List<String>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.aspectRatio(1f), contentAlignment = Alignment.Center) {
        val suffix = if (min(maxWidth.value, maxHeight.value) <= 128f) "thumb" else "full"
        for (layer in layers) {
            val id = cauldronAsset("$layer-$suffix")
            if (id != 0) Image(painterResource(id), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        }
    }
}

object DonutView : CauldronNativeView {
    override val name = "donut"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val layers = node.strings("layers")
        val background = node.string("background")
        if (background == null) {
            DonutLayers(layers, Modifier.fillMaxSize())
        } else {
            val colour = cauldronAssetColour(background)
            val shade = Brush.verticalGradient(listOf(colour.copy(alpha = 0.85f), colour))
            Box(
                Modifier.fillMaxSize()
                    .background(shade, CircleShape)
                    .border(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), CircleShape)
                    .padding(start = 6.dp, end = 6.dp, top = 5.dp, bottom = 6.dp)
            ) {
                DonutLayers(layers, Modifier.fillMaxSize().shadow(2.dp, CircleShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.15f)))
            }
        }
    }
}

@Composable
fun DonutStack(donuts: List<List<String>>, modifier: Modifier = Modifier, overflow: Boolean = false) {
    Box(modifier) {
        DiagonalStack(Modifier.fillMaxSize()) {
            for (layers in donuts.take(3)) DonutLayers(layers)
        }
        val extra = donuts.size - 3
        if (extra > 0 && overflow) {
            Text(
                "+$extra",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp)
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                    .padding(horizontal = 4.dp, vertical = 2.dp)
            )
        }
    }
}

@Composable
private fun DiagonalStack(modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val side = min(constraints.maxWidth, constraints.maxHeight).takeIf { it != Constraints.Infinity } ?: 180
        val count = measurables.size
        val placed = measurables.mapIndexed { index, measurable ->
            val share = when {
                count == 1 -> 1f to 1f
                count == 2 -> 0.7f to 0.7f
                index == 1 -> 0.65f to 0.65f
                else -> 0.7f to 0.65f
            }
            val size = (side * min(share.first, share.second)).roundToInt()
            measurable.measure(Constraints.fixed(size, size)) to index
        }
        layout(side, side) {
            val center = side / 2f
            for ((placeable, index) in placed) {
                val direction = if (index == 0) -1f else 1f
                val (dx, dy) = when {
                    count == 1 -> 0f to 0f
                    count == 2 -> side * direction * 0.15f to side * direction * 0.20f
                    index == 1 -> 0f to 0f
                    else -> side * direction * 0.15f to side * direction * 0.23f
                }
                placeable.place((center + dx - placeable.width / 2f).roundToInt(), (center + dy - placeable.height / 2f).roundToInt())
            }
        }
    }
}

object DonutStackView : CauldronNativeView {
    override val name = "donut_stack"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        DonutStack(node.layerLists("donuts"), Modifier.fillMaxSize(), node.bool("overflow"))
    }
}

object DonutBoxView : CauldronNativeView {
    override val name = "donut_box"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        var closed by remember { mutableStateOf(false) }
        var bounce by remember { mutableStateOf(false) }
        val drop by animateDpAsState(if (bounce) 15.dp else 0.dp, spring(dampingRatio = Spring.DampingRatioMediumBouncy), label = "bounce")
        val scope = rememberCoroutineScope()
        val toggle: suspend () -> Unit = {
            closed = !closed
            if (closed) {
                delay(150)
                bounce = true
                delay(150)
                bounce = false
            }
        }
        LaunchedEffect(Unit) {
            delay(750)
            toggle()
        }
        BoxWithConstraints(
            Modifier.fillMaxSize().aspectRatio(1f).offset(y = drop)
                .clickable(remember { MutableInteractionSource() }, null) { scope.launch { toggle() } },
            contentAlignment = Alignment.Center
        ) {
            val length = min(maxWidth.value, maxHeight.value)
            BoxPart("box/Inside")
            DonutLayers(node.strings("layers"), Modifier.padding(floor(length * 0.15f).dp).fillMaxSize())
            BoxPart("box/Bottom")
            AnimatedVisibility(
                closed,
                enter = fadeIn() + scaleIn(initialScale = 0.75f) + slideInVertically { -it / 2 },
                exit = fadeOut() + scaleOut(targetScale = 0.75f) + slideOutVertically { -it / 2 }
            ) { BoxPart("box/Lid") }
        }
    }

    @Composable
    private fun BoxPart(name: String) {
        val id = cauldronAsset(name)
        if (id != 0) Image(painterResource(id), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
    }
}
