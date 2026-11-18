package cauldron.app

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.BackNavigationBehavior
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.ColorUtils
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat

@Composable
internal fun NodeTheme(node: UiNode, modifier: Modifier) {
    val dark = when (node.string("scheme")) {
        "light" -> false
        "dark" -> true
        else -> isSystemInDarkTheme()
    }
    val context = LocalContext.current
    val accent = node.string("accent")?.let(::hexColor)
    val scheme = when {
        node.props["dynamic_color"] != false -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        accent != null -> seededScheme(accent, dark)
        else -> if (dark) darkColorScheme() else lightColorScheme()
    }
    val view = LocalView.current
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }
    MaterialTheme(colorScheme = scheme) {
        Surface(modifier = modifier.fillMaxSize()) {
            Column { shownChildren(node).forEach { NodeView(it) } }
            Presentations(node)
        }
    }
}

private fun seededScheme(seed: Color, dark: Boolean): ColorScheme {
    val hsl = FloatArray(3)
    ColorUtils.colorToHSL(seed.toArgb(), hsl)
    val hue = hsl[0]
    val tone = { h: Float, saturation: Float, lightness: Float -> Color(ColorUtils.HSLToColor(floatArrayOf((h + 360f) % 360f, saturation, lightness))) }
    val strong = hsl[1].coerceIn(0.45f, 0.9f)
    val soft = strong * 0.35f
    val third = hue + 60f
    return if (dark) {
        darkColorScheme(
            primary = tone(hue, strong, 0.72f), onPrimary = tone(hue, strong, 0.14f),
            primaryContainer = tone(hue, strong, 0.26f), onPrimaryContainer = tone(hue, strong, 0.9f),
            secondary = tone(hue, soft, 0.74f), onSecondary = tone(hue, soft, 0.15f),
            secondaryContainer = tone(hue, soft, 0.27f), onSecondaryContainer = tone(hue, soft, 0.9f),
            tertiary = tone(third, soft, 0.74f), onTertiary = tone(third, soft, 0.15f),
            tertiaryContainer = tone(third, soft, 0.27f), onTertiaryContainer = tone(third, soft, 0.9f),
            background = tone(hue, 0.08f, 0.07f), surface = tone(hue, 0.08f, 0.07f),
            surfaceVariant = tone(hue, 0.1f, 0.25f), onSurfaceVariant = tone(hue, 0.1f, 0.8f),
            surfaceContainerLowest = tone(hue, 0.08f, 0.05f), surfaceContainerLow = tone(hue, 0.08f, 0.1f),
            surfaceContainer = tone(hue, 0.08f, 0.12f), surfaceContainerHigh = tone(hue, 0.08f, 0.16f),
            surfaceContainerHighest = tone(hue, 0.08f, 0.2f), outline = tone(hue, 0.08f, 0.55f)
        )
    } else {
        lightColorScheme(
            primary = tone(hue, strong, 0.32f), onPrimary = Color.White,
            primaryContainer = tone(hue, strong, 0.88f), onPrimaryContainer = tone(hue, strong, 0.12f),
            secondary = tone(hue, soft, 0.38f), onSecondary = Color.White,
            secondaryContainer = tone(hue, soft, 0.88f), onSecondaryContainer = tone(hue, soft, 0.13f),
            tertiary = tone(third, soft, 0.38f), onTertiary = Color.White,
            tertiaryContainer = tone(third, soft, 0.88f), onTertiaryContainer = tone(third, soft, 0.13f),
            background = tone(hue, 0.15f, 0.985f), surface = tone(hue, 0.15f, 0.985f),
            surfaceVariant = tone(hue, 0.12f, 0.9f), onSurfaceVariant = tone(hue, 0.1f, 0.3f),
            surfaceContainerLowest = Color.White, surfaceContainerLow = tone(hue, 0.15f, 0.965f),
            surfaceContainer = tone(hue, 0.15f, 0.95f), surfaceContainerHigh = tone(hue, 0.15f, 0.93f),
            surfaceContainerHighest = tone(hue, 0.15f, 0.91f), outline = tone(hue, 0.08f, 0.47f)
        )
    }
}

@OptIn(ExperimentalMaterial3AdaptiveApi::class, ExperimentalMaterial3Api::class)
@Composable
internal fun NodeSplit(node: UiNode, modifier: Modifier) {
    val parts = node.children.mapNotNull { CauldronUi.node(it) }
    val sidebar = parts.firstOrNull { it.type == "sidebar" }
    val detail = parts.firstOrNull { it.type == "detail" }
    val selected = node.double("selected")?.toInt() ?: -1
    val navigator = rememberListDetailPaneScaffoldNavigator<Int>()
    val narrow = navigator.scaffoldDirective.maxHorizontalPartitions == 1
    val deselect = { UiEvents(node.id).send("select", null) }
    LaunchedEffect(selected) {
        if (selected >= 0) navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, selected)
        else if (navigator.canNavigateBack(BackNavigationBehavior.PopUntilScaffoldValueChange)) navigator.navigateBack()
    }
    BackHandler(enabled = narrow && selected >= 0) { deselect() }
    ListDetailPaneScaffold(
        modifier = modifier,
        directive = navigator.scaffoldDirective,
        value = navigator.scaffoldValue,
        listPane = {
            AnimatedPane {
                Scaffold(topBar = { TopAppBar(title = { Text(node.string("title") ?: "") }) }) { padding ->
                    SidebarRows(node, sidebar, selected, Modifier.padding(padding))
                }
            }
        },
        detailPane = {
            AnimatedPane {
                CompositionLocalProvider(LocalBack provides if (narrow && selected >= 0) deselect else null) {
                    Column(modifier = Modifier.fillMaxSize()) { detail?.children?.forEach { NodeView(it) } }
                }
            }
        }
    )
}

@Composable
private fun SidebarRows(split: UiNode, sidebar: UiNode?, selected: Int, modifier: Modifier) {
    var next = 0
    val entries = mutableListOf<Pair<String?, List<Pair<Int, UiNode>>>>()
    for (child in sidebar?.children.orEmpty().mapNotNull { CauldronUi.node(it) }) {
        if (child.type == "section") {
            entries += child.string("title") to child.children.mapNotNull { CauldronUi.node(it) }.map { next++ to it }
        } else {
            entries += null to listOf(next++ to child)
        }
    }
    LazyColumn(modifier = modifier.fillMaxSize().padding(horizontal = 12.dp)) {
        entries.forEach { (title, rows) ->
            if (title != null) {
                item {
                    Text(
                        title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp)
                    )
                }
            }
            rows.forEach { (index, row) ->
                item {
                    NavigationDrawerItem(
                        label = { Text(row.string("title") ?: "") },
                        icon = (row.string("icon") ?: row.string("asset"))?.let { name -> { NodeGlyph(row, name) } },
                        selected = index == selected,
                        onClick = { UiEvents(split.id).send("select", index) }
                    )
                }
            }
        }
    }
}

@Composable
internal fun NodeTable(node: UiNode, modifier: Modifier) {
    val columns = (node.props["columns"] as? List<*>)?.map { it.toString() }.orEmpty()
    val rows = (node.props["rows"] as? List<*>)?.map { row -> (row as? List<*>).orEmpty() }.orEmpty()
    val widths = (node.props["widths"] as? List<*>)?.map { (it as? Number)?.toFloat() }.orEmpty()
    val select: ((Int) -> Unit)? = if ("select" in node.events) ({ index -> UiEvents(node.id).send("select", index) }) else null
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        if (maxWidth >= 600.dp) WideTable(node, columns, widths, rows, select) else NarrowTable(node, rows, select)
    }
}

private fun cellText(cell: Any?): String? = if (cell is Map<*, *>) null else cell?.toString()

private fun cellControl(node: UiNode, cell: Any?): String? {
    val index = ((cell as? Map<*, *>)?.get("child") as? Number)?.toInt() ?: return null
    return node.children.getOrNull(index)
}

@Composable
private fun TableCell(node: UiNode, cell: Any?) {
    val control = cellControl(node, cell)
    if (control != null) NodeView(control) else Text(cellText(cell) ?: "", style = MaterialTheme.typography.bodyMedium)
}

@Composable
private fun WideTable(node: UiNode, columns: List<String>, widths: List<Float?>, rows: List<List<Any?>>, select: ((Int) -> Unit)?) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        item {
            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                columns.forEachIndexed { index, title ->
                    Text(
                        title,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = widths.getOrNull(index)?.let { Modifier.width(it.dp) } ?: Modifier.weight(1f)
                    )
                }
            }
            HorizontalDivider()
        }
        itemsIndexed(rows) { index, cells ->
            val tap = select?.let { Modifier.clickable { it(index) } } ?: Modifier
            Row(modifier = Modifier.fillMaxWidth().then(tap).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                cells.forEachIndexed { column, cell ->
                    Box(widths.getOrNull(column)?.let { Modifier.width(it.dp) } ?: Modifier.weight(1f)) { TableCell(node, cell) }
                }
            }
            HorizontalDivider()
        }
    }
}

@Composable
private fun NarrowTable(node: UiNode, rows: List<List<Any?>>, select: ((Int) -> Unit)?) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        itemsIndexed(rows) { index, cells ->
            val tap = select?.let { Modifier.clickable { it(index) } } ?: Modifier
            ListItem(
                headlineContent = { TableCell(node, cells.firstOrNull()) },
                supportingContent = cells.drop(1).mapNotNull(::cellText).filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }?.let { rest -> { Text(rest.joinToString(" · ")) } },
                modifier = tap
            )
            HorizontalDivider()
        }
    }
}
