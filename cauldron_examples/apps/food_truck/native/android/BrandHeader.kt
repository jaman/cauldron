package foodtruck

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import cauldron.app.CauldronAssets
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode
import cauldron.app.cauldronAssetColour
import kotlin.math.floor

private val turning = listOf(
    Triple("header/layer/1 Small Clouds", 760.0, 0.0),
    Triple("header/layer/2 Medium Clouds", 720.0, -15.0),
    Triple("header/layer/3 Mountains", 840.0, -10.0),
    Triple("header/layer/4 Big Clouds", 400.0, 0.0),
    Triple("header/layer/5 Ocean", 480.0, 0.0),
    Triple("header/layer/6 Balloons", 540.0, 0.0),
    Triple("header/layer/7 Trees", 180.0, -10.0)
)

object BrandHeaderView : CauldronNativeView {
    override val name = "brand_header"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val scale = if (node.bool("reduced")) 0.5f else 1f
        val animated = !node.bool("still")
        val context = LocalContext.current
        val bitmap = @Composable { name: String -> ImageBitmap.imageResource(CauldronAssets.drawable(context, name)) }
        val background = turning.map { (name, period, offset) -> Triple(bitmap(name), period, offset) }
        val foreground = bitmap("header/layer/9 Foreground")
        val road = bitmap("header/layer/8 Road")
        val frames = (1..4).map { bitmap("header/truck/Frame $it") }
        val skyStart = cauldronAssetColour("header/Sky Start")
        val skyEnd = cauldronAssetColour("header/Sky End")
        var time by remember { mutableDoubleStateOf(System.currentTimeMillis() / 1000.0) }
        LaunchedEffect(animated) {
            while (animated) withFrameNanos { time = System.currentTimeMillis() / 1000.0 }
        }

        Canvas(Modifier.fillMaxSize().clipToBounds()) {
            val point = density
            val centerX = size.width / 2
            translate(top = -200f * scale * point) {
                drawRect(Brush.radialGradient(listOf(skyStart, skyEnd), center = Offset(centerX, 400f * scale * point), radius = 600f * point), size = size.copy(height = size.height + 200f * scale * point))
                for ((image, period, offset) in background) {
                    turned(image, centerX, ((750 + offset) * scale * point).toFloat(), turn(time, period), scale)
                }
                placed(road, centerX, 350f * scale * point, scale)
                val cycle = 4.0 / 12.0
                val frame = floor((time % cycle) / cycle * 4).toInt().coerceIn(0, 3)
                placed(frames[frame], centerX, 307f * scale * point, scale)
                turned(foreground, centerX, 770f * scale * point, turn(time, 96.0), scale)
            }
        }
    }

    private fun turn(time: Double, period: Double): Float = ((time % period) / period * 360.0).toFloat()

    private fun DrawScope.turned(image: ImageBitmap, x: Float, y: Float, degrees: Float, scale: Float) {
        translate(x, y) {
            rotate(-degrees, pivot = Offset.Zero) {
                scale(scale, pivot = Offset.Zero) { drawImage(image, Offset(-image.width / 2f, -image.height / 2f)) }
            }
        }
    }

    private fun DrawScope.placed(image: ImageBitmap, x: Float, y: Float, scale: Float) {
        translate(x, y) {
            scale(scale, pivot = Offset.Zero) { drawImage(image, Offset(-image.width / 2f, -image.height / 2f)) }
        }
    }
}

