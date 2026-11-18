package cauldron.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.RowScope
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The app's Home Screen widgets: each kind's content is the JSON `CauldronNative.Widget`
 * sends, a timeline of entries each holding a control per size, drawn with Glance by the
 * kind's widget class, which the build generates with its receiver
 * (`CauldronWidgetKinds`). The content is kept in each placed widget's Glance state, and
 * in the app's files for widgets placed later; an alarm redraws the widgets when the next
 * entry is due.
 */
object CauldronWidgets {
    val CONTENT = stringPreferencesKey("cauldron_content")
    private val scope = CoroutineScope(Dispatchers.Default)

    fun update(context: Context, request: JSONObject) {
        val kind = request.getString("kind")
        val widget = CauldronWidgetKinds.widget(kind) ?: return
        val content = request.getJSONObject("content").toString()
        val file = file(context, kind)
        file.parentFile?.mkdirs()
        file.writeText(content)
        scope.launch {
            for (id in GlanceAppWidgetManager(context).getGlanceIds(widget.javaClass)) {
                updateAppWidgetState(context, id) { state -> state[CONTENT] = content }
                widget.update(context, id)
            }
        }
        next(context, kind, JSONObject(content))
    }

    fun stored(context: Context, kind: String): String? =
        file(context, kind).takeIf { it.exists() }?.readText()

    fun current(content: JSONObject): JSONObject? {
        val entries = content.optJSONArray("entries") ?: return null
        val now = System.currentTimeMillis() / 1000.0
        var shown: JSONObject? = if (entries.length() > 0) entries.getJSONObject(0) else null
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            if (entry.optDouble("at") <= now) shown = entry
        }
        return shown?.optJSONObject("sizes")
    }

    fun sized(sizes: JSONObject, size: DpSize): JSONObject? {
        val name = when {
            size.width >= 250.dp && size.height >= 250.dp -> "large"
            size.width >= 250.dp -> "medium"
            else -> "small"
        }
        val fallbacks = if (name == "large") listOf("large", "extra_large", "medium") else listOf(name)
        val chosen = (fallbacks + "default").firstNotNullOfOrNull { sizes.optJSONObject(it) }
        return chosen ?: sizes.keys().asSequence().firstNotNullOfOrNull { sizes.optJSONObject(it) }
    }

    fun next(context: Context, kind: String, content: JSONObject) {
        val entries = content.optJSONArray("entries") ?: return
        val now = System.currentTimeMillis() / 1000.0
        val due = (0 until entries.length()).map { entries.getJSONObject(it).optDouble("at") }.filter { it > now }.minOrNull() ?: return
        val receiver = ComponentName(context, "cauldron.app.CauldronWidgetReceiver_$kind")
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(receiver)
        if (ids.isEmpty()) return
        val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(receiver).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        val pending = PendingIntent.getBroadcast(context, kind.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        context.getSystemService(AlarmManager::class.java).set(AlarmManager.RTC, (due * 1000).toLong(), pending)
    }

    private fun file(context: Context, kind: String) = File(context.filesDir, "widgets/$kind.json")
}

/** A widget kind drawn from its content, or its `name` until it has some. */
open class CauldronGlanceWidget(private val kind: String, private val name: String) : GlanceAppWidget() {
    override val stateDefinition = PreferencesGlanceStateDefinition
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val stored = CauldronWidgets.stored(context, kind)
        stored?.let { CauldronWidgets.next(context, kind, JSONObject(it)) }
        provideContent {
            val json = currentState(CauldronWidgets.CONTENT) ?: stored
            val size = LocalSize.current
            val content = json?.let { CauldronWidgets.current(JSONObject(it)) }?.let { CauldronWidgets.sized(it, size) }
            val gradient = content?.optJSONObject("props")?.optJSONObject("modifiers")?.optJSONArray("gradient")
            GlanceTheme {
                Box(
                    GlanceModifier.fillMaxSize()
                        .then(
                            if (gradient != null) GlanceModifier.background(ImageProvider(gradientBitmap(context, gradient, size)), ContentScale.FillBounds)
                            else GlanceModifier.background(GlanceTheme.colors.widgetBackground)
                        )
                        .cornerRadius(16.dp)
                        .padding(14.dp)
                        .clickable(actionStartActivity<CauldronActivity>()),
                    contentAlignment = Alignment.TopStart
                ) {
                    if (content == null) Text(name, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant))
                    else WidgetNode(context, content)
                }
            }
        }
    }
}

private fun gradientBitmap(context: Context, colours: JSONArray, size: DpSize): Bitmap {
    val density = context.resources.displayMetrics.density
    val width = (size.width.value * density).toInt().coerceAtLeast(1)
    val height = (size.height.value * density).toInt().coerceAtLeast(1)
    val stops = (0 until colours.length()).map { plainColour(context, colours.opt(it)).toArgb() }.let { if (it.size == 1) it + it else it }
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val paint = Paint().apply { shader = LinearGradient(0f, 0f, width.toFloat(), height.toFloat(), stops.toIntArray(), null, Shader.TileMode.CLAMP) }
    Canvas(bitmap).drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    return bitmap
}

private fun plainColour(context: Context, value: Any?): Color = when {
    value is JSONArray && value.optString(0) == "asset" -> {
        val id = CauldronAssets.colour(context, value.optString(1))
        if (id == 0) Color.Gray else Color(context.getColor(id))
    }
    value == "white" -> Color.White
    value is String -> hexColor(value) ?: Color.Gray
    else -> Color.Gray
}

@Composable
private fun WidgetNode(context: Context, node: JSONObject, modifier: GlanceModifier = GlanceModifier, inherited: Any? = null) {
    val props = node.optJSONObject("props") ?: JSONObject()
    val own = props.optJSONObject("modifiers") ?: JSONObject()
    val look = if (own.has("foreground") || inherited == null) own else JSONObject(own.toString()).put("foreground", inherited)
    val foreground = look.opt("foreground")
    val padded = framed(modifier.padding(look.optDouble("padding", 0.0).toFloat().dp), look)
    val children = node.optJSONArray("children") ?: JSONArray()
    val spacing = props.optDouble("spacing", 6.0).toFloat().dp
    when (node.optString("type")) {
        "text" -> Text(props.optString("content"), modifier = padded, style = textStyle(context, look))
        "label" -> Row(padded, verticalAlignment = Alignment.CenterVertically) {
            WidgetIcon(context, props, look)
            Spacer(GlanceModifier.width(6.dp))
            Text(props.optString("title"), style = textStyle(context, look))
        }
        "icon" -> WidgetIcon(context, props, look)
        "image" -> WidgetImage(context, props.optString("asset"), padded)
        "gauge" -> WidgetGauge(context, props, look, padded)
        "vstack" -> Column(padded, horizontalAlignment = horizontal(props.optString("alignment"))) { ColumnChildren(context, children, spacing, foreground) }
        "hstack" -> Row(padded, verticalAlignment = Alignment.CenterVertically) { RowChildren(context, children, spacing, foreground) }
        "zstack" -> Box(padded, contentAlignment = Alignment.Center) { for (index in 0 until children.length()) WidgetNode(context, children.getJSONObject(index), inherited = foreground) }
        "divider" -> Box(GlanceModifier.fillMaxWidth().height(1.dp).background(GlanceTheme.colors.outline)) {}
        "progress" -> LinearProgressIndicator(
            progress = props.optDouble("value", 0.0).toFloat(),
            modifier = padded.fillMaxWidth(),
            color = GlanceTheme.colors.primary,
            backgroundColor = GlanceTheme.colors.surfaceVariant
        )
    }
}

private fun framed(modifier: GlanceModifier, look: JSONObject): GlanceModifier {
    val frame = look.optJSONObject("frame") ?: return modifier
    var framed = modifier
    if (frame.optString("max_width") == "infinity") framed = framed.fillMaxWidth()
    if (frame.has("width") && frame.has("height")) framed = framed.size(frame.optDouble("width").toFloat().dp, frame.optDouble("height").toFloat().dp)
    return framed
}

private fun horizontal(name: String): Alignment.Horizontal = when (name) {
    "center" -> Alignment.CenterHorizontally
    "trailing" -> Alignment.End
    else -> Alignment.Start
}

@Composable
private fun WidgetImage(context: Context, asset: String, modifier: GlanceModifier) {
    val id = CauldronAssets.drawable(context, asset)
    if (id != 0) Image(ImageProvider(id), contentDescription = null, contentScale = ContentScale.Fit, modifier = modifier)
}

@Composable
private fun WidgetGauge(context: Context, props: JSONObject, look: JSONObject, modifier: GlanceModifier) {
    val low = props.optDouble("min", 0.0)
    val high = maxOf(props.optDouble("max", 1.0), low + 0.0001)
    val value = props.optDouble("value", 0.0).coerceIn(low, high)
    val tint = look.opt("tint")?.let { colour(context, it, GlanceTheme.colors.primary) } ?: GlanceTheme.colors.primary
    Column(modifier.fillMaxWidth()) {
        props.optString("title").ifEmpty { null }?.let { Text(it, style = textStyle(context, look)) }
        if (props.optString("style") == "segmented") {
            Row(GlanceModifier.fillMaxWidth().height(11.dp)) {
                for (index in 0 until maxOf(high.toInt(), 1)) {
                    if (index > 0) Spacer(GlanceModifier.width(3.dp))
                    Box(GlanceModifier.defaultWeight().height(11.dp).cornerRadius(2.dp).background(if (index < value) tint else GlanceTheme.colors.surfaceVariant)) {}
                }
            }
        } else {
            LinearProgressIndicator(
                progress = ((value - low) / (high - low)).toFloat(),
                modifier = GlanceModifier.fillMaxWidth(),
                color = tint,
                backgroundColor = ColorProvider(Color.White.copy(alpha = 0.3f))
            )
        }
        val images = props.optJSONArray("image")
        if (images != null) {
            Spacer(GlanceModifier.height(6.dp))
            Box(GlanceModifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                for (index in 0 until images.length()) WidgetImage(context, images.optString(index), GlanceModifier.size(28.dp))
            }
        } else {
            props.optString("current").ifEmpty { null }?.let { Text(it, style = textStyle(context, look)) }
        }
    }
}

@Composable
private fun ColumnScope.ColumnChildren(context: Context, children: JSONArray, spacing: androidx.compose.ui.unit.Dp, foreground: Any?) {
    for (index in 0 until children.length()) {
        val child = children.getJSONObject(index)
        if (index > 0) Spacer(GlanceModifier.height(spacing))
        if (child.optString("type") == "spacer") Spacer(GlanceModifier.defaultWeight())
        else WidgetNode(context, child, inherited = foreground)
    }
}

@Composable
private fun RowScope.RowChildren(context: Context, children: JSONArray, spacing: androidx.compose.ui.unit.Dp, foreground: Any?) {
    for (index in 0 until children.length()) {
        val child = children.getJSONObject(index)
        if (index > 0) Spacer(GlanceModifier.width(spacing))
        if (child.optString("type") == "spacer") Spacer(GlanceModifier.defaultWeight())
        else WidgetNode(context, child, inherited = foreground)
    }
}

@Composable
private fun WidgetIcon(context: Context, props: JSONObject, look: JSONObject) {
    val size = (fontSize(look.optString("font")) * 1.2f).toInt()
    val tint = ColorFilter.tint(colour(context, look.opt("foreground"), GlanceTheme.colors.primary))
    val asset = props.optString("asset").ifEmpty { null }?.let { CauldronAssets.drawable(context, it) } ?: 0
    if (asset != 0) {
        Image(ImageProvider(asset), contentDescription = null, modifier = GlanceModifier.size(size.dp), colorFilter = tint)
        return
    }
    val pixels = (size * context.resources.displayMetrics.density).toInt()
    val name = props.optString("icon").ifEmpty { props.optString("name") }.ifEmpty { null }
    val own = props.optString("android").ifEmpty { null }
    Image(provider = ImageProvider(CauldronIcons.bitmap(name, own, pixels)), contentDescription = null, modifier = GlanceModifier.size(size.dp), colorFilter = tint)
}

@Composable
private fun textStyle(context: Context, look: JSONObject): TextStyle {
    val font = look.optString("font")
    val bold = look.optBoolean("bold") || font in setOf("headline", "large_title", "title")
    return TextStyle(
        fontSize = fontSize(font).sp,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        color = colour(context, look.opt("foreground"), GlanceTheme.colors.onSurface)
    )
}

@Composable
private fun colour(context: Context, value: Any?, otherwise: ColorProvider): ColorProvider = when {
    value == "secondary" -> GlanceTheme.colors.onSurfaceVariant
    value == "accent" -> GlanceTheme.colors.primary
    value == "destructive" -> GlanceTheme.colors.error
    value == "white" || (value is String && value.startsWith("#")) || value is JSONArray -> ColorProvider(plainColour(context, value))
    else -> otherwise
}

private fun fontSize(name: String): Float = when (name) {
    "large_title" -> 30f
    "title" -> 26f
    "title2" -> 22f
    "title3" -> 20f
    "headline" -> 16f
    "subheadline" -> 14f
    "callout" -> 15f
    "footnote" -> 12f
    "caption" -> 12f
    else -> 15f
}
