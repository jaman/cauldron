package foodtruck

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode
import cauldron.app.cauldronAssetColour
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

private val indigo = Color(0xFF5856D6)
private val teal = Color(0xFF30B0C7)
private val yellow = Color(0xFFFFCC00)

private class Hour(val time: Long, val degrees: Float, val daylight: Boolean)

private fun DrawScope.label(text: String, x: Float, y: Float, colour: Color, alignRight: Boolean = false) {
    val paint = android.graphics.Paint().apply {
        isAntiAlias = true
        textSize = 11.sp.toPx()
        color = colour.toArgb()
        textAlign = if (alignRight) android.graphics.Paint.Align.RIGHT else android.graphics.Paint.Align.CENTER
    }
    drawContext.canvas.nativeCanvas.drawText(text, x, y, paint)
}

private fun smooth(points: List<Offset>): Path = Path().apply {
    if (points.isEmpty()) return@apply
    moveTo(points[0].x, points[0].y)
    for (index in 0 until points.size - 1) {
        val previous = points.getOrElse(index - 1) { points[index] }
        val start = points[index]
        val end = points[index + 1]
        val next = points.getOrElse(index + 2) { end }
        cubicTo(
            start.x + (end.x - previous.x) / 6f, start.y + (end.y - previous.y) / 6f,
            end.x - (next.x - start.x) / 6f, end.y - (next.y - start.y) / 6f,
            end.x, end.y
        )
    }
}

object ForecastChartView : CauldronNativeView {
    override val name = "forecast_chart"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val hours = (node.props["entries"] as? List<*>).orEmpty().mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            Hour(((map["time"] as? Number)?.toLong() ?: return@mapNotNull null) * 1000, (map["degrees"] as? Number)?.toFloat() ?: 0f, map["daylight"] != false)
        }
        val unit = node.string("unit") ?: "°"
        val ink = MaterialTheme.colorScheme.onSurfaceVariant
        val grid = MaterialTheme.colorScheme.outlineVariant
        if (hours.size < 2) return
        Canvas(Modifier.fillMaxWidth().height(200.dp)) {
            val right = 44.dp.toPx()
            val bottom = 22.dp.toPx()
            val plot = Size(size.width - right, size.height - bottom)
            val low = hours.minOf { it.degrees } - 2f
            val top = ceil(hours.maxOf { it.degrees } / 5f) * 5f
            val start = hours.first().time
            val span = (hours.last().time - start).toFloat()
            fun x(time: Long) = (time - start) / span * plot.width
            fun y(degrees: Float) = plot.height - (degrees - low) / (top - low) * plot.height

            var tick = ceil(low / 5f) * 5f
            while (tick <= top) {
                drawLine(grid, Offset(0f, y(tick)), Offset(plot.width, y(tick)), 1f)
                label("${tick.toInt()}$unit", size.width, y(tick) + 4.dp.toPx(), ink, alignRight = true)
                tick += 5f
            }
            for (hour in hours) {
                val hourOfDay = Calendar.getInstance().apply { timeInMillis = hour.time }.get(Calendar.HOUR_OF_DAY)
                if (hourOfDay % 3 == 0) {
                    drawLine(grid, Offset(x(hour.time), 0f), Offset(x(hour.time), plot.height), 1f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f)))
                    label("$hourOfDay", x(hour.time), size.height - 4.dp.toPx(), ink)
                }
            }

            val curve = smooth(hours.map { Offset(x(it.time), y(it.degrees)) })
            val area = Path().apply {
                addPath(curve)
                lineTo(plot.width, plot.height)
                lineTo(0f, plot.height)
                close()
            }
            drawPath(area, Brush.verticalGradient(listOf(yellow, teal), startY = 0f, endY = plot.height))

            for ((from, to) in nights(hours)) {
                clipPath(area) { drawRect(indigo.copy(alpha = 0.5f), Offset(x(from), 0f), Size(x(to) - x(from), plot.height)) }
                if (from != hours.first().time) edge(x(from), y(hours.first { it.time == from }.degrees), plot.height, moon = true)
                if (to != hours.last().time) edge(x(to), y(hours.first { it.time == to }.degrees), plot.height, moon = false)
            }
        }
    }

    private fun nights(hours: List<Hour>): List<Pair<Long, Long>> {
        val ranges = mutableListOf<Pair<Long, Long>>()
        var start: Long? = null
        for (hour in hours) {
            if (hour.daylight && start != null) {
                ranges.add(start to hour.time)
                start = null
            } else if (!hour.daylight && start == null) {
                start = hour.time
            }
        }
        start?.let { ranges.add(it to hours.last().time) }
        return ranges
    }

    private fun DrawScope.edge(x: Float, y: Float, bottom: Float, moon: Boolean) {
        drawRoundRect(indigo, Offset(x - 2.dp.toPx(), y), Size(4.dp.toPx(), bottom - y), CornerRadius(2.dp.toPx()))
        val radius = 10.dp.toPx()
        val center = Offset(x, y - radius - 5.dp.toPx())
        drawCircle(indigo, radius, center)
        if (moon) {
            drawCircle(Color.White, radius * 0.55f, center)
            drawCircle(indigo, radius * 0.5f, center + Offset(radius * 0.3f, -radius * 0.2f))
        } else {
            drawCircle(Color.White, radius * 0.35f, center)
            for (ray in 0 until 8) {
                val angle = Math.toRadians(ray * 45.0)
                val inner = center + Offset((radius * 0.5f * Math.cos(angle)).toFloat(), (radius * 0.5f * Math.sin(angle)).toFloat())
                val outer = center + Offset((radius * 0.72f * Math.cos(angle)).toFloat(), (radius * 0.72f * Math.sin(angle)).toFloat())
                drawLine(Color.White, inner, outer, 1.5.dp.toPx())
            }
        }
    }
}

object TopSalesChartView : CauldronNativeView {
    override val name = "top_sales_chart"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val sales = (node.props["sales"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
            .map { Triple(it["name"]?.toString() ?: "", (it["layers"] as? List<*>).orEmpty().map(Any?::toString), (it["sales"] as? Number)?.toInt() ?: 0) }
            .sortedWith(compareBy({ it.third }, { it.first }))
        val total = sales.sumOf { it.third }
        val most = max(sales.maxOfOrNull { it.third } ?: 1, 1)
        val step = niceStep(most)
        val top = ceil(most / step.toFloat()) * step
        val bottomColour = cauldronAssetColour("BarBottomColor")
        val accent = MaterialTheme.colorScheme.primary
        val grid = MaterialTheme.colorScheme.outlineVariant
        val ink = MaterialTheme.colorScheme.onSurfaceVariant
        Column(Modifier.fillMaxWidth()) {
            Text("Total Sales", style = MaterialTheme.typography.bodyMedium, color = ink)
            Text("${"%,d".format(total)} Donuts", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            BoxWithConstraints(Modifier.fillMaxWidth().height(340.dp).padding(top = 20.dp)) {
                val plotHeight = maxHeight - 84.dp
                Canvas(Modifier.fillMaxWidth().height(plotHeight)) {
                    var tick = 0f
                    while (tick <= top) {
                        val y = size.height - tick / top * size.height
                        drawLine(grid, Offset(0f, y), Offset(size.width - 36.dp.toPx(), y), 1f)
                        label("${tick.toInt()}", size.width, y + 4.dp.toPx(), ink, alignRight = true)
                        tick += step
                    }
                }
                Row(Modifier.fillMaxSize().padding(end = 36.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((name, layers, sold) in sales) {
                        Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(Modifier.height(plotHeight).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(
                                        "%,d".format(sold),
                                        fontSize = 11.sp,
                                        modifier = Modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp)
                                    )
                                    Spacer(Modifier.height(4.dp))
                                    Box(
                                        Modifier.fillMaxWidth().height(plotHeight * (sold / top) - 28.dp * (sold / top))
                                            .background(Brush.verticalGradient(listOf(accent, bottomColour)), RoundedCornerShape(6.dp))
                                    )
                                }
                            }
                            DonutLayers(layers, Modifier.size(35.dp))
                            Text(name, fontSize = 11.sp, textAlign = TextAlign.Center, maxLines = 2, minLines = 2, color = ink)
                        }
                    }
                }
            }
        }
    }

    private fun niceStep(most: Int): Int {
        val rough = most / 4.0
        val magnitude = Math.pow(10.0, floor(Math.log10(max(rough, 1.0))))
        val steps = listOf(1.0, 2.0, 2.5, 5.0, 10.0).map { it * magnitude }
        return steps.first { it >= rough }.toInt().coerceAtLeast(1)
    }
}

object SalesHistoryChartView : CauldronNativeView {
    override val name = "sales_history_chart"

    private val colours = listOf(Color(0xFF007AFF), Color(0xFF34C759), Color(0xFFFF9500))

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val cities = (node.props["cities"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }.map { city ->
            val entries = (city["entries"] as? List<*>).orEmpty().mapNotNull { pair ->
                val values = pair as? List<*> ?: return@mapNotNull null
                ((values[0] as Number).toLong() * 1000) to (values[1] as Number).toFloat()
            }.sortedBy { it.first }
            (city["name"]?.toString() ?: "") to entries
        }
        val locked = node.bool("locked")
        val ink = MaterialTheme.colorScheme.onSurfaceVariant
        val grid = MaterialTheme.colorScheme.outlineVariant
        val format = SimpleDateFormat("MMM d", Locale.getDefault())
        Column(Modifier.fillMaxWidth()) {
            Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                cities.forEachIndexed { index, (name, _) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).background(colours[index % colours.size], CircleShape))
                        Spacer(Modifier.width(4.dp))
                        Text(name, fontSize = 11.sp, color = ink)
                    }
                }
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 300.dp)) {
                Canvas(Modifier.fillMaxWidth().height(300.dp)) {
                    val all = cities.flatMap { it.second }
                    if (all.isEmpty()) return@Canvas
                    val right = 40.dp.toPx()
                    val bottom = 22.dp.toPx()
                    val plot = Size(size.width - right, size.height - bottom)
                    val low = floor(all.minOf { it.second } / 100f) * 100f
                    val high = ceil(all.maxOf { it.second } / 100f) * 100f
                    val start = all.minOf { it.first }
                    val span = max((all.maxOf { it.first } - start).toFloat(), 1f)
                    fun x(time: Long) = (time - start) / span * plot.width
                    fun y(value: Float) = plot.height - (value - low) / max(high - low, 1f) * plot.height
                    var tick = low
                    while (tick <= high) {
                        drawLine(grid, Offset(0f, y(tick)), Offset(plot.width, y(tick)), 1f)
                        label("${tick.toInt()}", size.width, y(tick) + 4.dp.toPx(), ink, alignRight = true)
                        tick += 100f
                    }
                    val days = all.map { it.first }.distinct().sorted()
                    val every = max(days.size / 6, 1)
                    days.forEachIndexed { index, day ->
                        if (index % every == 0 && index < days.size - 1) {
                            drawLine(grid, Offset(x(day), 0f), Offset(x(day), plot.height), 1f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f)))
                            label(format.format(Date(day)), x(day), size.height - 4.dp.toPx(), ink)
                        }
                    }
                    if (!locked) {
                        cities.forEachIndexed { index, (_, entries) ->
                            val colour = colours[index % colours.size]
                            val points = entries.map { Offset(x(it.first), y(it.second)) }
                            drawPath(smooth(points), colour, style = Stroke(2.dp.toPx()))
                            for (point in points) symbol(index, point, colour)
                        }
                    }
                }
                if (locked) {
                    Box(Modifier.fillMaxWidth().height(278.dp).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                        Row(
                            Modifier.shadow(6.dp, RoundedCornerShape(50)).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(50)).padding(20.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Outlined.Lock, null, tint = ink)
                            Spacer(Modifier.width(6.dp))
                            Text("Premium Feature", color = ink)
                        }
                    }
                }
            }
        }
    }

    private fun DrawScope.symbol(index: Int, at: Offset, colour: Color) {
        val radius = 3.dp.toPx()
        val stroke = Stroke(1.5.dp.toPx())
        when (index % 3) {
            0 -> drawCircle(colour, radius, at, style = stroke)
            1 -> drawRect(colour, at - Offset(radius, radius), Size(radius * 2, radius * 2), style = stroke)
            else -> drawPath(Path().apply {
                moveTo(at.x, at.y - radius)
                lineTo(at.x + radius, at.y + radius)
                lineTo(at.x - radius, at.y + radius)
                close()
            }, colour, style = stroke)
        }
    }
}
