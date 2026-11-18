package cauldron.app

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.compose.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.compose.cartesian.Zoom
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoScrollState
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.compose.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.compose.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberAxisLabelComponent
import com.patrykandpatrick.vico.compose.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.compose.cartesian.data.CartesianLayerRangeProvider
import com.patrykandpatrick.vico.compose.cartesian.data.CartesianValueFormatter
import com.patrykandpatrick.vico.compose.cartesian.data.columnSeries
import com.patrykandpatrick.vico.compose.cartesian.data.lineSeries
import com.patrykandpatrick.vico.compose.cartesian.layer.CartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.layer.ColumnCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.layer.LineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberColumnCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.common.Fill
import com.patrykandpatrick.vico.compose.common.HorizontalLegend
import com.patrykandpatrick.vico.compose.common.LegendItem
import com.patrykandpatrick.vico.compose.common.MeasuringContext
import com.patrykandpatrick.vico.compose.common.DrawingContext
import com.patrykandpatrick.vico.compose.common.ProvideVicoTheme
import com.patrykandpatrick.vico.compose.common.component.ShapeComponent
import com.patrykandpatrick.vico.compose.common.component.TextComponent
import com.patrykandpatrick.vico.compose.common.component.rememberLineComponent
import com.patrykandpatrick.vico.compose.common.component.rememberShapeComponent
import com.patrykandpatrick.vico.compose.common.component.rememberTextComponent
import com.patrykandpatrick.vico.compose.m3.common.rememberM3VicoTheme
import com.patrykandpatrick.vico.compose.pie.PieChart
import com.patrykandpatrick.vico.compose.pie.PieChartHost
import com.patrykandpatrick.vico.compose.pie.PieSize
import com.patrykandpatrick.vico.compose.pie.data.PieChartModelProducer
import com.patrykandpatrick.vico.compose.pie.data.pieSeries
import com.patrykandpatrick.vico.compose.pie.rememberPieChart
import java.text.DateFormat
import java.util.Date

private class ChartSeries(val name: String, val mark: String, val colour: Color?, val xs: List<Any?>, val ys: List<Double>)

@Composable
internal fun NodeChart(node: UiNode, modifier: Modifier) {
    val series = chartSeries(node)
    val sized = if (hasFrameHeight(node)) modifier else modifier.height(240.dp)
    val palette = palette(series)
    ProvideVicoTheme(rememberM3VicoTheme()) {
        if (series.firstOrNull()?.mark == "sector") {
            PieNode(node, series.first(), palette, sized)
        } else {
            CartesianNode(node, series, palette, sized)
        }
    }
}

@Composable
private fun CartesianNode(node: UiNode, series: List<ChartSeries>, palette: List<Color>, modifier: Modifier) {
    val xType = node.string("x_type") ?: "number"
    val categories = series.flatMap { it.xs }.map { it.toString() }.distinct()
    val bars = series.withIndex().filter { it.value.mark == "bar" }
    val lines = series.withIndex().filter { it.value.mark != "bar" }
    val range = yRange(node)
    val producer = remember { CartesianChartModelProducer() }

    LaunchedEffect(node.props) {
        producer.runTransaction {
            if (bars.isNotEmpty()) columnSeries { bars.forEach { (_, one) -> series(x = xValues(one, xType, categories), y = one.ys) } }
            if (lines.isNotEmpty()) lineSeries { lines.forEach { (_, one) -> series(x = xValues(one, xType, categories), y = one.ys) } }
        }
    }

    val layers = mutableListOf<CartesianLayer<*>>()
    if (bars.isNotEmpty()) {
        layers += rememberColumnCartesianLayer(
            columnProvider = ColumnCartesianLayer.ColumnProvider.series(
                bars.map { (index, _) -> rememberLineComponent(Fill(palette[index]), 12.dp) }
            ),
            rangeProvider = range
        )
    }
    if (lines.isNotEmpty()) {
        layers += rememberLineCartesianLayer(
            lineProvider = LineCartesianLayer.LineProvider.series(lines.map { (index, one) -> line(one.mark, palette[index]) }),
            rangeProvider = range
        )
    }

    val labels = rememberAxisLabelComponent()
    val formatter = remember(xType, categories) { xFormatter(xType, categories) }
    val legend = if (node.bool("legend")) legend(series, palette) else null
    CartesianChartHost(
        chart = rememberCartesianChart(
            *layers.toTypedArray(),
            startAxis = VerticalAxis.rememberStart(titleComponent = labels, title = { node.string("y_label") }),
            bottomAxis = HorizontalAxis.rememberBottom(
                valueFormatter = formatter,
                titleComponent = labels,
                title = { node.string("x_label") }
            ),
            legend = legend
        ),
        modelProducer = producer,
        modifier = modifier,
        scrollState = rememberVicoScrollState(scrollEnabled = false),
        zoomState = rememberVicoZoomState(
            zoomEnabled = false,
            initialZoom = Zoom.Content,
            minZoom = Zoom.Content,
            maxZoom = Zoom.Content
        )
    )
}

@Composable
private fun line(mark: String, colour: Color): LineCartesianLayer.Line = when (mark) {
    "area" -> LineCartesianLayer.rememberLine(
        fill = LineCartesianLayer.LineFill.single(Fill(colour)),
        areaFill = LineCartesianLayer.AreaFill.single(Fill(colour.copy(alpha = 0.3f)))
    )
    "point" -> LineCartesianLayer.rememberLine(
        fill = LineCartesianLayer.LineFill.single(Fill(Color.Transparent)),
        pointProvider = LineCartesianLayer.PointProvider.single(
            LineCartesianLayer.Point(rememberShapeComponent(Fill(colour), CircleShape), 8.dp)
        )
    )
    else -> LineCartesianLayer.rememberLine(fill = LineCartesianLayer.LineFill.single(Fill(colour)))
}

@Composable
private fun PieNode(node: UiNode, series: ChartSeries, palette: List<Color>, modifier: Modifier) {
    val producer = remember { PieChartModelProducer() }
    LaunchedEffect(node.props) { producer.runTransaction { pieSeries { series(series.ys) } } }
    val label = rememberTextComponent(TextStyle(color = MaterialTheme.colorScheme.onPrimary, fontSize = 12.sp))
    val colours = series.xs.indices.map { palette[it % palette.size] }
    val slices = colours.map { PieChart.Slice(fill = Fill(it), label = PieChart.SliceLabel.Inside(label)) }
    val items = series.xs.map { it.toString() }.zip(colours)
    PieChartHost(
        chart = rememberPieChart(
            sliceProvider = PieChart.SliceProvider.series(slices),
            innerSize = if (node.bool("donut")) PieSize.Inner.fixed(96.dp) else PieSize.Inner.Zero,
            legend = legendOf(items)
        ),
        modelProducer = producer,
        modifier = modifier
    )
}

@Composable
private fun legend(series: List<ChartSeries>, palette: List<Color>): HorizontalLegend<CartesianMeasuringContext, CartesianDrawingContext> =
    legendOf(series.mapIndexed { index, one -> one.name to palette[index] })

@Composable
private fun <M : MeasuringContext, D : DrawingContext> legendOf(items: List<Pair<String, Color>>): HorizontalLegend<M, D> {
    val text = rememberTextComponent(TextStyle(color = MaterialTheme.colorScheme.onSurface, fontSize = 12.sp))
    return remember(items, text) {
        HorizontalLegend(
            items = { items.forEach { (name, colour) -> add(LegendItem(ShapeComponent(Fill(colour), CircleShape), text, name)) } },
            padding = com.patrykandpatrick.vico.compose.common.Insets(top = 8.dp)
        )
    }
}

@Composable
private fun palette(series: List<ChartSeries>): List<Color> {
    val scheme = MaterialTheme.colorScheme
    val defaults = listOf(scheme.primary, scheme.tertiary, scheme.secondary, scheme.error, scheme.primaryContainer, scheme.tertiaryContainer)
    val count = maxOf(series.size, series.firstOrNull()?.xs?.size ?: 0)
    return (0 until maxOf(count, 1)).map { index -> series.getOrNull(index)?.colour ?: defaults[index % defaults.size] }
}

private fun yRange(node: UiNode): CartesianLayerRangeProvider {
    val range = node.props["y_range"] as? List<*>
    val low = (range?.getOrNull(0) as? Number)?.toDouble()
    val high = (range?.getOrNull(1) as? Number)?.toDouble()
    return if (low != null && high != null) CartesianLayerRangeProvider.fixed(minY = low, maxY = high) else CartesianLayerRangeProvider.auto()
}

private fun xValues(series: ChartSeries, xType: String, categories: List<String>): List<Double> = series.xs.map { x ->
    when (xType) {
        "category" -> categories.indexOf(x.toString()).toDouble()
        "date" -> ((x as? Number)?.toDouble() ?: 0.0) / 86_400_000.0
        else -> (x as? Number)?.toDouble() ?: 0.0
    }
}

private fun xFormatter(xType: String, categories: List<String>): CartesianValueFormatter = when (xType) {
    "category" -> CartesianValueFormatter { _, value, _ -> categories.getOrNull(value.toInt()) ?: "" }
    "date" -> {
        val format = DateFormat.getDateInstance(DateFormat.SHORT)
        CartesianValueFormatter { _, value, _ -> format.format(Date((value * 86_400_000.0).toLong())) }
    }
    else -> CartesianValueFormatter.decimal()
}

@Suppress("UNCHECKED_CAST")
private fun chartSeries(node: UiNode): List<ChartSeries> = (node.props["series"] as? List<Map<String, Any?>> ?: emptyList()).map { raw ->
    val points = (raw["points"] as? List<List<Any?>> ?: emptyList()).filter { it.size == 2 && it[1] is Number }
    ChartSeries(
        name = raw["name"] as? String ?: "",
        mark = raw["mark"] as? String ?: "bar",
        colour = (raw["colour"] as? String)?.let(::hexColor),
        xs = points.map { it[0] },
        ys = points.map { (it[1] as Number).toDouble() }
    )
}

internal fun hasFrameHeight(node: UiNode): Boolean = node.modifiers.any { pair ->
    pair.firstOrNull() == "frame" && (pair.getOrNull(1) as? Map<*, *>)?.containsKey("height") == true
}
