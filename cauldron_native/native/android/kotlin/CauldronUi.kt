package cauldron.app

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import org.json.JSONArray
import org.json.JSONObject

class UiNode(val id: String, type: String, props: Map<String, Any?>, events: Set<String>, children: List<String>) {
    var type by mutableStateOf(type)
    var props by mutableStateOf(props)
    var events by mutableStateOf(events)
    var children by mutableStateOf(children)

    fun string(key: String): String? = props[key] as? String
    fun bool(key: String): Boolean = props[key] as? Boolean ?: false
    fun double(key: String): Double? = (props[key] as? Number)?.toDouble()

    @Suppress("UNCHECKED_CAST")
    val modifiers: List<List<Any?>> get() = props["modifiers"] as? List<List<Any?>> ?: emptyList()
}

class UiEvents(private val id: String) {
    fun send(kind: String, value: Any? = null) {
        val message = JSONObject().put("id", id).put("kind", kind)
        if (value != null) message.put("value", value)
        CauldronActivity.uiEvent(message.toString().toByteArray(Charsets.UTF_8))
    }
}

interface CauldronNativeView {
    val name: String

    @Composable
    fun Content(node: UiNode, events: UiEvents)
}

object CauldronUi {
    private val nodes = mutableStateMapOf<String, UiNode>()
    private var root by mutableStateOf<String?>(null)
    private var shownIn: CauldronActivity? = null
    private val main = Handler(Looper.getMainLooper())

    @JvmStatic
    fun patch(json: ByteArray) {
        val patch = JSONObject(String(json, Charsets.UTF_8))
        main.post {
            apply(patch)
            show()
        }
    }

    @JvmStatic
    fun show() {
        val activity = CauldronActivity.current ?: return
        if (shownIn === activity || root == null) return
        shownIn = activity
        activity.showNativeUi(ComposeView(activity).apply { setContent { Root() } })
    }

    private fun apply(patch: JSONObject) {
        val records = patch.optJSONArray("nodes") ?: JSONArray()
        for (index in 0 until records.length()) update(records.getJSONObject(index))
        val removed = patch.optJSONArray("removed") ?: JSONArray()
        for (index in 0 until removed.length()) nodes.remove(removed.getString(index))
        val newRoot = patch.optString("root", "")
        if (newRoot.isNotEmpty() && newRoot != root) root = newRoot
    }

    @Suppress("UNCHECKED_CAST")
    private fun update(record: JSONObject) {
        val id = record.getString("id")
        val type = record.getString("type")
        val props = plain(record.optJSONObject("props") ?: JSONObject()) as Map<String, Any?>
        val events = (plain(record.optJSONArray("events") ?: JSONArray()) as List<Any?>).map { it as String }.toSet()
        val children = (plain(record.optJSONArray("children") ?: JSONArray()) as List<Any?>).map { it as String }
        val node = nodes[id]
        if (node == null) {
            nodes[id] = UiNode(id, type, props, events, children)
            return
        }
        if (node.type != type) node.type = type
        if (node.props != props) node.props = props
        if (node.events != events) node.events = events
        if (node.children != children) node.children = children
    }

    private fun plain(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { plain(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { plain(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    fun node(id: String): UiNode? = nodes[id]

    private fun reportWindow(width: Float, height: Float) {
        val window = JSONObject().put("width", width).put("height", height).put("compact", width < 600f)
        CauldronActivity.uiEvent(JSONObject().put("window", window).toString().toByteArray(Charsets.UTF_8))
    }

    @Composable
    private fun Root() {
        val dark = isSystemInDarkTheme()
        val context = LocalContext.current
        val view = LocalView.current
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
        MaterialTheme(colorScheme = if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)) {
            Surface(modifier = Modifier.fillMaxSize()) {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val width = maxWidth.value
                    val height = maxHeight.value
                    LaunchedEffect(width, height) { reportWindow(width, height) }
                    root?.let { NodeView(it) }
                }
            }
        }
    }
}

internal val LocalEnabled = compositionLocalOf { true }
internal val LocalBack = compositionLocalOf<(() -> Unit)?> { null }

@Composable
fun NodeView(id: String) {
    val node = CauldronUi.node(id) ?: return
    val enabled = LocalEnabled.current && !node.bool("disabled")
    val style = textStyle(node.modifiers, LocalTextStyle.current)
    val color = contentColor(node.modifiers) ?: LocalContentColor.current
    CompositionLocalProvider(LocalEnabled provides enabled, LocalTextStyle provides style, LocalContentColor provides color) {
        NodeContent(node, uiModifier(node))
    }
}

@Composable
private fun NodeContent(node: UiNode, modifier: Modifier) {
    when (node.type) {
        "text" -> Text(node.string("content") ?: "", modifier = modifier)
        "button" -> NodeButton(node, modifier)
        "text_field", "secure_field" -> NodeTextField(node, modifier)
        "toggle" -> NodeToggle(node, modifier)
        "slider" -> NodeSlider(node, modifier)
        "vstack" -> Column(
            modifier = modifier,
            verticalArrangement = spacing(node),
            horizontalAlignment = horizontalAlignment(node.string("alignment"))
        ) { ColumnChildren(node) }
        "hstack" -> Row(
            modifier = modifier,
            horizontalArrangement = rowSpacing(node),
            verticalAlignment = verticalAlignment(node.string("alignment"))
        ) { RowChildren(node) }
        "zstack" -> Box(modifier = modifier, contentAlignment = boxAlignment(node.string("alignment"))) {
            node.children.forEach { NodeView(it) }
        }
        "spacer" -> Spacer(modifier = modifier)
        "divider" -> HorizontalDivider(modifier = modifier)
        "scroll" -> if (node.string("axis") == "horizontal") {
            Row(modifier = modifier.horizontalScroll(rememberScrollState())) { RowChildren(node) }
        } else {
            Column(modifier = modifier.verticalScroll(rememberScrollState())) { ColumnChildren(node) }
        }
        "list", "form" -> LazyColumn(modifier = modifier.fillMaxSize()) { rows(node) }
        "section" -> Column(modifier = modifier) { SectionContent(node) }
        "navigation" -> NodeNavigation(node, modifier)
        "screen" -> NodeScreen(node, modifier)
        "native" -> NodeNative(node, modifier)
        "icon" -> NodeIcon(node, modifier)
        "image" -> NodeImage(node, modifier)
        "gauge" -> NodeGauge(node, modifier)
        "label" -> NodeLabel(node, modifier)
        "link" -> NodeLink(node, modifier)
        "menu" -> NodeMenu(node, modifier)
        "chip" -> NodeChip(node, modifier)
        "picker" -> NodePicker(node, modifier)
        "date_picker" -> NodeDatePicker(node, modifier)
        "stepper" -> NodeStepper(node, modifier)
        "progress" -> NodeProgress(node, modifier)
        "text_editor" -> NodeTextField(node, modifier)
        "card" -> NodeCard(node, modifier)
        "grid" -> NodeGrid(node, modifier)
        "disclosure" -> NodeDisclosure(node, modifier)
        "tabs" -> NodeTabs(node, modifier)
        "tab" -> TabBody(node, modifier)
        "video" -> NodeVideo(node, modifier)
        "camera_preview" -> NodeCameraPreview(node, modifier)
        "chart" -> NodeChart(node, modifier)
        "map" -> NodeMap(node, modifier)
        "split" -> NodeSplit(node, modifier)
        "table" -> NodeTable(node, modifier)
        "theme" -> NodeTheme(node, modifier)
    }
}

@Composable
private fun ColumnScope.ColumnChildren(node: UiNode) {
    shownChildren(node).forEach { id ->
        if (CauldronUi.node(id)?.type == "spacer") Spacer(Modifier.weight(1f)) else NodeView(id)
    }
}

private val wrappingTypes = setOf("text", "vstack", "label")

@Composable
private fun RowScope.RowChildren(node: UiNode) {
    val shown = shownChildren(node)
    val types = shown.map { CauldronUi.node(it)?.type }
    val firstSpacer = types.indexOf("spacer")
    val grower = if (firstSpacer > 0 && types[firstSpacer - 1] in wrappingTypes) firstSpacer - 1 else -1
    shown.forEachIndexed { index, id ->
        when {
            index == grower -> Box(Modifier.weight(1f)) { NodeView(id) }
            index == firstSpacer && grower >= 0 -> Unit
            types[index] == "spacer" -> Spacer(Modifier.weight(1f))
            types[index] == "divider" -> VerticalDivider(Modifier.fillMaxHeight())
            else -> NodeView(id)
        }
    }
}

private fun LazyListScope.rows(node: UiNode) {
    shownChildren(node).forEach { id ->
        if (CauldronUi.node(id)?.type == "section") {
            item(key = id) { SectionHeader(id) }
            CauldronUi.node(id)?.children?.forEach { row -> item(key = row) { ListRow(row) } }
            item(key = "$id/footer") { SectionFooter(id) }
        } else {
            item(key = id) { ListRow(id) }
        }
    }
}

@Composable
private fun ListRow(id: String) {
    val node = CauldronUi.node(id) ?: return
    if (node.type == "text" && node.modifiers.isEmpty()) {
        ListItem(headlineContent = { NodeView(id) })
    } else if (node.type == "button" && node.string("style") == null) {
        ButtonRow(node)
    } else {
        Box(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) { NodeView(id) }
    }
}

@Composable
internal fun ButtonRow(node: UiNode) {
    val enabled = LocalEnabled.current && !node.bool("disabled")
    val color = when {
        !enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
        node.string("role") == "destructive" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }
    ListItem(
        headlineContent = { Text(node.string("title") ?: "", color = color) },
        leadingContent = (node.string("icon") ?: node.string("asset"))?.let { name -> { NodeGlyph(node, name, tint = color) } },
        modifier = Modifier.clickable(enabled = enabled, onClickLabel = node.string("hint")) { UiEvents(node.id).send("tap") }
    )
}

@Composable
private fun SectionHeader(id: String) {
    val title = CauldronUi.node(id)?.string("title") ?: return
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp)
    )
}

@Composable
private fun SectionFooter(id: String) {
    val footer = CauldronUi.node(id)?.string("footer") ?: return
    Text(
        footer,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun SectionContent(node: UiNode) {
    SectionHeader(node.id)
    node.children.forEach { ListRow(it) }
    SectionFooter(node.id)
}

@Composable
private fun NodeButton(node: UiNode, modifier: Modifier) {
    val enabled = LocalEnabled.current
    val tap = { UiEvents(node.id).send("tap") }
    val title: @Composable () -> Unit = {
        node.string("icon")?.let {
            Icon(iconFor(it, node.string("android")), contentDescription = null)
            Spacer(Modifier.width(8.dp))
        }
        Text(node.string("title") ?: "")
    }
    val destructive = node.string("role") == "destructive"
    when (node.string("style")) {
        "prominent" -> Button(
            onClick = tap,
            enabled = enabled,
            modifier = modifier,
            colors = if (destructive) ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error) else ButtonDefaults.buttonColors()
        ) { title() }
        "bordered" -> OutlinedButton(onClick = tap, enabled = enabled, modifier = modifier) { title() }
        "icon" -> IconButton(onClick = tap, enabled = enabled, modifier = modifier) {
            Icon(iconFor(node.string("icon"), node.string("android")), contentDescription = node.string("title"))
        }
        else -> TextButton(
            onClick = tap,
            enabled = enabled,
            modifier = modifier,
            colors = if (destructive) ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error) else ButtonDefaults.textButtonColors()
        ) { title() }
    }
}

@Composable
private fun NodeTextField(node: UiNode, modifier: Modifier) {
    var text by remember { mutableStateOf(node.string("value") ?: "") }
    val sent = remember { mutableListOf<String>() }
    val value = node.string("value") ?: ""
    LaunchedEffect(value) {
        val echoed = sent.indexOf(value)
        if (echoed >= 0) {
            repeat(echoed + 1) { sent.removeAt(0) }
        } else if (value != text) {
            sent.clear()
            text = value
        }
    }
    OutlinedTextField(
        value = text,
        onValueChange = {
            text = it
            if ("change" in node.events) {
                sent.add(it)
                UiEvents(node.id).send("change", it)
            }
        },
        label = { Text(node.string("placeholder") ?: "") },
        enabled = LocalEnabled.current,
        singleLine = node.type != "text_editor",
        minLines = if (node.type == "text_editor") 3 else 1,
        visualTransformation = if (node.type == "secure_field") PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            keyboardType = keyboardType(node),
            capitalization = capitalization(node.string("capitalize")),
            autoCorrectEnabled = node.props["autocorrect"] as? Boolean ?: true,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { if ("submit" in node.events) UiEvents(node.id).send("submit", text) }),
        modifier = modifier.fillMaxWidth()
    )
}

@Composable
private fun NodeToggle(node: UiNode, modifier: Modifier) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(node.string("title") ?: "", modifier = Modifier.weight(1f))
        Switch(
            checked = node.bool("value"),
            onCheckedChange = { UiEvents(node.id).send("change", it) },
            enabled = LocalEnabled.current,
            modifier = hinted(node.string("hint")) { UiEvents(node.id).send("change", !node.bool("value")) }
        )
    }
}

@Composable
private fun NodeSlider(node: UiNode, modifier: Modifier) {
    val low = node.double("min") ?: 0.0
    val high = node.double("max") ?: 1.0
    val steps = node.double("step")?.let { ((high - low) / it).toInt() - 1 }?.coerceAtLeast(0) ?: 0
    Slider(
        value = (node.double("value") ?: low).toFloat(),
        onValueChange = { UiEvents(node.id).send("change", it.toDouble()) },
        valueRange = low.toFloat()..high.toFloat(),
        steps = steps,
        enabled = LocalEnabled.current,
        modifier = modifier
    )
}

@Composable
private fun NodeNavigation(node: UiNode, modifier: Modifier) {
    val depth = node.children.size
    val back = if (depth > 1 && "back" in node.events) ({ UiEvents(node.id).send("back", depth - 1) }) else null
    BackHandler(enabled = back != null) { back?.invoke() }
    val top = node.children.lastOrNull() ?: return
    AnimatedContent(
        targetState = top,
        modifier = modifier,
        transitionSpec = {
            val forward = node.children.indexOf(targetState) >= node.children.indexOf(initialState)
            if (forward) {
                slideInHorizontally { it } togetherWith slideOutHorizontally { -it / 3 }
            } else {
                slideInHorizontally { -it / 3 } togetherWith slideOutHorizontally { it }
            }
        },
        label = "navigation"
    ) { screen ->
        CompositionLocalProvider(LocalBack provides if (screen == node.children.first()) null else back) {
            NodeView(screen)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NodeScreen(node: UiNode, modifier: Modifier) {
    val back = LocalBack.current
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(node.string("title") ?: "") },
                navigationIcon = {
                    if (back != null) {
                        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                    }
                },
                actions = { ToolbarItems(node) }
            )
        }
    ) { padding ->
        CompositionLocalProvider(LocalBack provides null) {
            Column(modifier = Modifier.padding(padding).consumeWindowInsets(padding).fillMaxSize()) {
                SearchField(node)
                val shown = shownChildren(node)
                if (shown.size == 1) {
                    Box(modifier = Modifier.weight(1f).fillMaxWidth()) { NodeView(shown.first()) }
                } else {
                    ColumnChildren(node)
                }
            }
            Presentations(node)
        }
    }
}

@Composable
private fun NodeTabs(node: UiNode, modifier: Modifier) {
    val selected = node.double("selected")?.toInt() ?: 0
    val tabs = node.children.mapNotNull { CauldronUi.node(it) }
    NavigationSuiteScaffold(
        modifier = modifier,
        navigationSuiteItems = {
            tabs.forEachIndexed { index, tab ->
                item(
                    selected = index == selected,
                    onClick = { UiEvents(node.id).send("select", index) },
                    icon = { Icon(iconFor(tab.string("icon"), tab.string("android")), contentDescription = null) },
                    label = { Text(tab.string("title") ?: "") }
                )
            }
        }
    ) {
        tabs.getOrNull(selected)?.let { TabBody(it, Modifier.fillMaxSize()) }
    }
}

@Composable
private fun TabBody(tab: UiNode, modifier: Modifier) {
    val shown = shownChildren(tab)
    Box(modifier = modifier) {
        if (shown.size == 1) NodeView(shown.first()) else Column { shown.forEach { NodeView(it) } }
    }
}

@Composable
private fun NodeNative(node: UiNode, modifier: Modifier) {
    val view = cauldronNativeViews[node.string("name") ?: ""]
    if (view == null) {
        Text("No native view named ${node.string("name")}", color = MaterialTheme.colorScheme.error, modifier = modifier)
    } else {
        Box(modifier = modifier) { view.Content(node, UiEvents(node.id)) }
    }
}

@Composable
private fun uiModifier(node: UiNode): Modifier {
    var modifier: Modifier = Modifier
    for (pair in platformModifiers(node.modifiers).asReversed()) modifier = modifier.then(layoutModifier(pair))
    node.string("label")?.let { label -> modifier = modifier.semantics { contentDescription = label } }
    if ("tap" in node.events) modifier = modifier.then(hinted(node.string("hint")) { UiEvents(node.id).send("tap") })
    return modifier
}

private fun hinted(hint: String?, action: () -> Unit): Modifier =
    if (hint == null) Modifier else Modifier.semantics { onClick(label = hint) { action(); true } }

private fun platformModifiers(list: List<List<Any?>>): List<List<Any?>> = list.flatMap { pair ->
    @Suppress("UNCHECKED_CAST")
    when (pair.firstOrNull()) {
        "android" -> platformModifiers(pair.getOrNull(1) as? List<List<Any?>> ?: emptyList())
        "ios" -> emptyList()
        else -> listOf(pair)
    }
}

@Composable
private fun layoutModifier(pair: List<Any?>): Modifier {
    val value = pair.getOrNull(1)
    return when (pair.firstOrNull()) {
        "padding" -> Modifier.padding(paddingValues(value))
        "background" -> Modifier.background(color(value))
        "gradient" -> Modifier.background(Brush.linearGradient((value as? List<*>).orEmpty().map { color(it) }.ifEmpty { listOf(Color.Transparent, Color.Transparent) }.let { if (it.size == 1) it + it else it }))
        "frame" -> frame(value)
        "corner_radius" -> Modifier.clip(RoundedCornerShape(((value as? Number)?.toFloat() ?: 0f).dp))
        "opacity" -> Modifier.alpha((value as? Number)?.toFloat() ?: 1f)
        else -> Modifier
    }
}

private fun paddingValues(value: Any?): PaddingValues {
    if (value == true) return PaddingValues(16.dp)
    if (value is Number) return PaddingValues(value.toFloat().dp)
    val edges = value as? Map<*, *> ?: return PaddingValues(0.dp)
    fun edge(vararg keys: String) = (keys.firstNotNullOfOrNull { edges[it] as? Number }?.toFloat() ?: 0f).dp
    return PaddingValues(
        start = edge("leading", "horizontal", "all"),
        top = edge("top", "vertical", "all"),
        end = edge("trailing", "horizontal", "all"),
        bottom = edge("bottom", "vertical", "all")
    )
}

private fun frame(value: Any?): Modifier {
    val frame = value as? Map<*, *> ?: return Modifier
    var modifier: Modifier = Modifier
    (frame["width"] as? Number)?.let { modifier = modifier.width(it.toFloat().dp) }
    (frame["height"] as? Number)?.let { modifier = modifier.height(it.toFloat().dp) }
    (frame["min_width"] as? Number)?.let { modifier = modifier.widthIn(min = it.toFloat().dp) }
    (frame["min_height"] as? Number)?.let { modifier = modifier.heightIn(min = it.toFloat().dp) }
    when (val maxWidth = frame["max_width"]) {
        "infinity" -> modifier = modifier.fillMaxWidth()
        is Number -> modifier = modifier.widthIn(max = maxWidth.toFloat().dp)
    }
    when (val maxHeight = frame["max_height"]) {
        "infinity" -> modifier = modifier.fillMaxHeight()
        is Number -> modifier = modifier.heightIn(max = maxHeight.toFloat().dp)
    }
    return modifier
}

@Composable
private fun textStyle(modifiers: List<List<Any?>>, inherited: TextStyle): TextStyle {
    var style = inherited
    for (pair in platformModifiers(modifiers)) {
        when (pair.firstOrNull()) {
            "font" -> style = typography(pair.getOrNull(1) as? String)
            "bold" -> if (pair.getOrNull(1) == true) style = style.copy(fontWeight = FontWeight.Bold)
        }
    }
    return style
}

@Composable
private fun contentColor(modifiers: List<List<Any?>>): Color? =
    platformModifiers(modifiers).lastOrNull { it.firstOrNull() == "foreground" }?.let { color(it.getOrNull(1)) }

@Composable
private fun typography(name: String?): TextStyle {
    val type = MaterialTheme.typography
    return when (name) {
        "large_title" -> type.headlineLarge
        "title" -> type.headlineMedium
        "title2" -> type.headlineSmall
        "title3" -> type.titleLarge
        "headline" -> type.titleMedium
        "callout", "subheadline" -> type.bodyMedium
        "footnote" -> type.bodySmall
        "caption" -> type.labelSmall
        else -> type.bodyLarge
    }
}

@Composable
private fun color(value: Any?): Color {
    val scheme = MaterialTheme.colorScheme
    return when (value) {
        "primary" -> scheme.onSurface
        "secondary" -> scheme.onSurfaceVariant
        "accent" -> scheme.primary
        "background" -> scheme.surface
        "secondary_background" -> scheme.surfaceContainer
        "destructive" -> scheme.error
        is String -> hexColor(value) ?: scheme.onSurface
        is List<*> -> if (value.getOrNull(0) == "asset") cauldronAssetColour(value.getOrNull(1).toString()) else scheme.onSurface
        else -> scheme.onSurface
    }
}

internal fun hexColor(text: String): Color? {
    val digits = text.removePrefix("#")
    if (digits.length != 6) return null
    val value = digits.toLongOrNull(16) ?: return null
    return Color(0xFF000000 or value)
}

private fun spacing(node: UiNode): Arrangement.Vertical =
    node.double("spacing")?.let { Arrangement.spacedBy(it.toFloat().dp) } ?: Arrangement.spacedBy(8.dp)

private fun rowSpacing(node: UiNode): Arrangement.Horizontal =
    node.double("spacing")?.let { Arrangement.spacedBy(it.toFloat().dp) } ?: Arrangement.spacedBy(8.dp)

private fun horizontalAlignment(name: String?): Alignment.Horizontal = when (name) {
    "leading" -> Alignment.Start
    "trailing" -> Alignment.End
    else -> Alignment.CenterHorizontally
}

private fun verticalAlignment(name: String?): Alignment.Vertical = when (name) {
    "top" -> Alignment.Top
    "bottom" -> Alignment.Bottom
    else -> Alignment.CenterVertically
}

private fun boxAlignment(name: String?): Alignment = when (name) {
    "top" -> Alignment.TopCenter
    "top_leading" -> Alignment.TopStart
    "top_trailing" -> Alignment.TopEnd
    "bottom_leading" -> Alignment.BottomStart
    "bottom_trailing" -> Alignment.BottomEnd
    "bottom" -> Alignment.BottomCenter
    "leading" -> Alignment.CenterStart
    "trailing" -> Alignment.CenterEnd
    else -> Alignment.Center
}

private fun keyboardType(node: UiNode): KeyboardType = when {
    node.type == "secure_field" -> KeyboardType.Password
    else -> when (node.string("keyboard")) {
        "email" -> KeyboardType.Email
        "number" -> KeyboardType.Number
        "decimal" -> KeyboardType.Decimal
        "phone" -> KeyboardType.Phone
        "url" -> KeyboardType.Uri
        else -> KeyboardType.Text
    }
}

private fun capitalization(name: String?): KeyboardCapitalization = when (name) {
    "words" -> KeyboardCapitalization.Words
    "characters" -> KeyboardCapitalization.Characters
    "none" -> KeyboardCapitalization.None
    else -> KeyboardCapitalization.Sentences
}
