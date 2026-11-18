package cauldron.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset

internal val attachedTypes = setOf("toolbar", "sheet", "alert", "confirm", "dialog")

internal fun shownChildren(node: UiNode): List<String> =
    node.children.filter { CauldronUi.node(it)?.type !in attachedTypes }

internal fun attachedChildren(node: UiNode, type: String): List<UiNode> =
    node.children.mapNotNull { CauldronUi.node(it) }.filter { it.type == type }

internal fun iconFor(name: String?, own: String? = null): ImageVector = own?.let(::materialIcon) ?: when (name) {
    "add" -> Icons.Filled.Add
    "add_circle" -> Icons.Filled.AddCircle
    "back" -> Icons.AutoMirrored.Filled.ArrowBack
    "forward" -> Icons.AutoMirrored.Filled.ArrowForward
    "phone" -> Icons.Filled.Call
    "check" -> Icons.Filled.Check
    "check_circle" -> Icons.Filled.CheckCircle
    "close" -> Icons.Filled.Close
    "calendar" -> Icons.Filled.DateRange
    "delete" -> Icons.Filled.Delete
    "edit" -> Icons.Filled.Edit
    "mail" -> Icons.Filled.Email
    "favorite" -> Icons.Filled.Favorite
    "favorite_border" -> Icons.Filled.FavoriteBorder
    "home" -> Icons.Filled.Home
    "info" -> Icons.Filled.Info
    "location" -> Icons.Filled.LocationOn
    "lock" -> Icons.Filled.Lock
    "menu" -> Icons.Filled.Menu
    "more" -> Icons.Filled.MoreVert
    "notifications" -> Icons.Filled.Notifications
    "person" -> Icons.Filled.Person
    "account" -> Icons.Filled.AccountCircle
    "play" -> Icons.Filled.PlayArrow
    "refresh" -> Icons.Filled.Refresh
    "search" -> Icons.Filled.Search
    "send" -> Icons.AutoMirrored.Filled.Send
    "settings" -> Icons.Filled.Settings
    "share" -> Icons.Filled.Share
    "cart" -> Icons.Filled.ShoppingCart
    "star" -> Icons.Filled.Star
    "thumb_up" -> Icons.Filled.ThumbUp
    "warning" -> Icons.Filled.Warning
    "list" -> Icons.AutoMirrored.Filled.List
    "face" -> Icons.Filled.Face
    "build" -> Icons.Filled.Build
    else -> name?.let(::materialIcon) ?: Icons.Filled.Info
}

private fun materialIcon(name: String): ImageVector? {
    val pascal = name.split('_', '-').joinToString("") { part -> part.replaceFirstChar { it.uppercase() } }
    return runCatching {
        val holder = Class.forName("androidx.compose.material.icons.filled.${pascal}Kt")
        holder.getMethod("get$pascal", Icons.Filled::class.java).invoke(null, Icons.Filled) as ImageVector
    }.getOrNull()
}

@Composable
internal fun NodeIcon(node: UiNode, modifier: Modifier) {
    NodeGlyph(node, node.string("name"), modifier)
}

private val pictures = LruCache<String, Bitmap>(32)

@Composable
internal fun NodeImage(node: UiNode, modifier: Modifier) {
    val asset = node.string("asset")
    if (asset != null) return NodeAsset(asset, node, modifier)
    val source = node.string("source") ?: ""
    val picture by produceState(pictures.get(source), source) {
        if (value == null) value = withContext(Dispatchers.IO) { load(source) }?.also { pictures.put(source, it) }
    }
    val scale = if (node.string("fit") == "fill") ContentScale.Crop else ContentScale.Fit
    val loaded = picture
    if (loaded != null) {
        val shape = if (scale == ContentScale.Fit) Modifier.aspectRatio(loaded.width.toFloat() / loaded.height.coerceAtLeast(1)) else Modifier
        Image(loaded.asImageBitmap(), contentDescription = node.string("label"), contentScale = scale, modifier = modifier.fillMaxWidth().then(shape))
    } else {
        Box(modifier = modifier.fillMaxWidth().heightIn(min = 48.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(modifier = Modifier.size(24.dp)) }
    }
}

@Composable
private fun NodeAsset(asset: String, node: UiNode, modifier: Modifier) {
    val id = cauldronAsset(asset)
    if (id == 0) return
    if (CauldronAssets.vector(LocalContext.current, id)) {
        Icon(painterResource(id), contentDescription = node.string("label"), modifier = modifier)
        return
    }
    val scale = if (node.string("fit") == "fill") ContentScale.Crop else ContentScale.Fit
    Image(painterResource(id), contentDescription = node.string("label"), contentScale = scale, modifier = modifier)
}

private fun load(source: String): Bitmap? = runCatching {
    if (source.startsWith("http://") || source.startsWith("https://")) {
        URL(source).openStream().use { BitmapFactory.decodeStream(it) }
    } else {
        BitmapFactory.decodeFile(source)
    }
}.getOrNull()

@Composable
internal fun NodeLabel(node: UiNode, modifier: Modifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        NodeGlyph(node, node.string("icon"))
        Spacer(Modifier.width(12.dp))
        Text(node.string("title") ?: "")
    }
}

@Composable
internal fun NodeLink(node: UiNode, modifier: Modifier) {
    val uri = LocalUriHandler.current
    TextButton(onClick = { node.string("url")?.let { runCatching { uri.openUri(it) } } }, modifier = modifier) {
        Text(node.string("title") ?: "")
    }
}

@Composable
internal fun NodeMenu(node: UiNode, modifier: Modifier) {
    var open by remember { mutableStateOf(false) }
    Box(modifier = modifier) {
        val icon = node.string("icon")
        if (icon != null) {
            IconButton(onClick = { open = true }) { Icon(iconFor(icon, node.string("android")), contentDescription = node.string("title")) }
        } else {
            TextButton(onClick = { open = true }) { Text(node.string("title") ?: "") }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            node.children.mapNotNull { CauldronUi.node(it) }.forEach { item ->
                DropdownMenuItem(
                    text = { Text(item.string("title") ?: "") },
                    leadingIcon = item.string("icon")?.let { name -> { Icon(iconFor(name, item.string("android")), contentDescription = null) } },
                    enabled = !item.bool("disabled"),
                    onClick = {
                        open = false
                        UiEvents(item.id).send("tap")
                    }
                )
            }
        }
    }
}

@Composable
internal fun NodeChip(node: UiNode, modifier: Modifier) {
    FilterChip(
        selected = node.bool("selected"),
        onClick = { UiEvents(node.id).send("tap") },
        label = { Text(node.string("title") ?: "") },
        enabled = LocalEnabled.current,
        modifier = modifier
    )
}

@Suppress("UNCHECKED_CAST")
private fun options(node: UiNode): List<String> = node.props["options"] as? List<String> ?: emptyList()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NodePicker(node: UiNode, modifier: Modifier) {
    val options = options(node)
    val selected = node.double("value")?.toInt() ?: -1
    val choose = { index: Int -> UiEvents(node.id).send("change", index) }
    when (node.string("style")) {
        "segmented" -> SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    selected = index == selected,
                    onClick = { choose(index) },
                    shape = SegmentedButtonDefaults.itemShape(index, options.size)
                ) { Text(option) }
            }
        }
        "inline" -> Column(modifier = modifier) {
            node.string("title")?.let { Text(it, style = MaterialTheme.typography.labelLarge) }
            options.forEachIndexed { index, option ->
                Row(
                    modifier = Modifier.fillMaxWidth().selectable(selected = index == selected, onClick = { choose(index) }),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(selected = index == selected, onClick = { choose(index) })
                    Text(option)
                }
            }
        }
        else -> {
            var open by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }, modifier = modifier) {
                OutlinedTextField(
                    value = options.getOrNull(selected) ?: "",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(node.string("title") ?: "") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = open) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
                )
                ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    options.forEachIndexed { index, option ->
                        DropdownMenuItem(text = { Text(option) }, onClick = {
                            open = false
                            choose(index)
                        })
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NodeDatePicker(node: UiNode, modifier: Modifier) {
    val mode = node.string("mode") ?: "date"
    val text = node.string("value") ?: ""
    val send = { value: String -> UiEvents(node.id).send("change", value) }
    if (node.string("style") == "graphical" && mode == "date") {
        val state = rememberDatePickerState(initialSelectedDateMillis = dayMillis(text))
        val chosen = state.selectedDateMillis
        LaunchedEffect(chosen) { if (chosen != null && chosen != dayMillis(text)) send(dayText(chosen)) }
        DatePicker(state = state, modifier = modifier)
        return
    }
    var opening by remember { mutableStateOf<String?>(null) }
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(node.string("title") ?: "", modifier = Modifier.weight(1f))
        if (mode != "time") TextButton(onClick = { opening = "date" }) { Text(text.take(10)) }
        if (mode != "date") TextButton(onClick = { opening = "time" }) { Text(timePart(text).take(5)) }
    }
    when (opening) {
        "date" -> {
            val state = rememberDatePickerState(initialSelectedDateMillis = dayMillis(text))
            DatePickerDialog(
                onDismissRequest = { opening = null },
                confirmButton = {
                    TextButton(onClick = {
                        opening = null
                        state.selectedDateMillis?.let { send(withDay(text, mode, dayText(it))) }
                    }) { Text("OK") }
                },
                dismissButton = { TextButton(onClick = { opening = null }) { Text("Cancel") } }
            ) { DatePicker(state = state) }
        }
        "time" -> {
            val time = runCatching { LocalTime.parse(timePart(text)) }.getOrElse { LocalTime.NOON }
            val state = rememberTimePickerState(time.hour, time.minute)
            AlertDialog(
                onDismissRequest = { opening = null },
                confirmButton = {
                    TextButton(onClick = {
                        opening = null
                        send(withTime(text, mode, LocalTime.of(state.hour, state.minute).toString() + ":00"))
                    }) { Text("OK") }
                },
                dismissButton = { TextButton(onClick = { opening = null }) { Text("Cancel") } },
                text = { TimePicker(state = state) }
            )
        }
    }
}

private fun timePart(text: String): String = if (text.contains('T')) text.substringAfter('T') else text

private fun dayMillis(text: String): Long? =
    runCatching { LocalDate.parse(text.take(10)).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()

private fun dayText(millis: Long): String =
    LocalDateTime.ofEpochSecond(millis / 1000, 0, ZoneOffset.UTC).toLocalDate().toString()

private fun withDay(text: String, mode: String, day: String): String =
    if (mode == "date_time") day + "T" + timePart(text) else day

private fun withTime(text: String, mode: String, time: String): String =
    if (mode == "date_time") text.take(10) + "T" + time else time

@Composable
internal fun NodeStepper(node: UiNode, modifier: Modifier) {
    val value = node.double("value") ?: 0.0
    val step = node.double("step") ?: 1.0
    val low = node.double("min") ?: Double.NEGATIVE_INFINITY
    val high = node.double("max") ?: Double.POSITIVE_INFINITY
    val shown = if (value == Math.rint(value)) value.toLong().toString() else value.toString()
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("${node.string("title") ?: ""}: $shown", modifier = Modifier.weight(1f))
        FilledTonalIconButton(onClick = { UiEvents(node.id).send("change", value - step) }, enabled = value - step >= low) { Text("−") }
        FilledTonalIconButton(onClick = { UiEvents(node.id).send("change", value + step) }, enabled = value + step <= high) {
            Icon(Icons.Filled.Add, contentDescription = "Increase")
        }
    }
}

@Composable
internal fun NodeProgress(node: UiNode, modifier: Modifier) {
    val value = node.double("value")?.toFloat()
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        node.string("title")?.let { Text(it) }
        when {
            node.string("style") == "circular" && value != null -> CircularProgressIndicator(progress = { value })
            node.string("style") == "circular" -> CircularProgressIndicator()
            value != null -> LinearProgressIndicator(progress = { value }, modifier = Modifier.fillMaxWidth())
            else -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
internal fun NodeCard(node: UiNode, modifier: Modifier) {
    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            shownChildren(node).forEach { NodeView(it) }
        }
    }
}

@Composable
internal fun NodeGrid(node: UiNode, modifier: Modifier) {
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val wanted = node.double("min_width")?.let { (maxWidth.value / it.toFloat()).toInt() }
        val columns = (wanted ?: node.double("columns")?.toInt() ?: 2).coerceAtLeast(1)
        val spacing = (node.double("spacing") ?: 12.0).toFloat().dp
        Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
            shownChildren(node).chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                    row.forEach { id -> Box(modifier = Modifier.weight(1f)) { NodeView(id) } }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
internal fun NodeDisclosure(node: UiNode, modifier: Modifier) {
    val expanded = node.bool("expanded")
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { UiEvents(node.id).send("toggle", !expanded) }.padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(node.string("title") ?: "", modifier = Modifier.weight(1f))
            Icon(if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, contentDescription = null)
        }
        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { shownChildren(node).forEach { NodeView(it) } }
        }
    }
}

@Composable
internal fun ActionButton(button: UiNode) {
    val color = if (button.string("role") == "destructive") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
    TextButton(onClick = { UiEvents(button.id).send("tap") }) { Text(button.string("title") ?: "", color = color) }
}

@Composable
internal fun ToolbarItems(node: UiNode) {
    attachedChildren(node, "toolbar").flatMap { bar -> bar.children.mapNotNull { CauldronUi.node(it) } }.forEach { item ->
        val icon = item.string("icon")
        if (item.type == "button" && icon != null) {
            IconButton(onClick = { UiEvents(item.id).send("tap") }, enabled = !item.bool("disabled")) {
                Icon(iconFor(icon, item.string("android")), contentDescription = item.string("title"))
            }
        } else {
            NodeView(item.id)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun Presentations(node: UiNode) {
    attachedChildren(node, "sheet").filter { it.bool("shown") }.forEach { sheet ->
        ModalBottomSheet(onDismissRequest = { UiEvents(sheet.id).send("dismiss") }) {
            Column(modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                sheet.string("title")?.let { Text(it, style = MaterialTheme.typography.titleLarge) }
                shownChildren(sheet).forEach { NodeView(it) }
            }
        }
    }
    attachedChildren(node, "alert").filter { it.bool("shown") }.forEach { alert ->
        val buttons = alert.children.mapNotNull { CauldronUi.node(it) }
        val (cancels, actions) = buttons.partition { it.string("role") == "cancel" }
        AlertDialog(
            onDismissRequest = { UiEvents(alert.id).send("dismiss") },
            title = { Text(alert.string("title") ?: "") },
            text = alert.string("message")?.let { message -> { Text(message) } },
            confirmButton = { Row { actions.forEach { ActionButton(it) } } },
            dismissButton = { Row { cancels.forEach { ActionButton(it) } } }
        )
    }
    attachedChildren(node, "dialog").filter { it.bool("shown") }.forEach { dialog ->
        val parts = dialog.children.mapNotNull { CauldronUi.node(it) }
        val content = parts.firstOrNull { it.type == "dialog_content" }
        val buttons = parts.firstOrNull { it.type == "dialog_actions" }?.children?.mapNotNull { CauldronUi.node(it) }.orEmpty()
        val (cancels, actions) = buttons.partition { it.string("role") == "cancel" }
        AlertDialog(
            onDismissRequest = { UiEvents(dialog.id).send("dismiss") },
            title = { Text(dialog.string("title") ?: "") },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    content?.children?.forEach { NodeView(it) }
                }
            },
            confirmButton = { Row { actions.forEach { ActionButton(it) } } },
            dismissButton = { Row { cancels.forEach { ActionButton(it) } } }
        )
    }
    attachedChildren(node, "confirm").filter { it.bool("shown") }.forEach { confirm ->
        ModalBottomSheet(onDismissRequest = { UiEvents(confirm.id).send("dismiss") }) {
            Column(modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp)) {
                Text(confirm.string("title") ?: "", style = MaterialTheme.typography.titleMedium)
                confirm.string("message")?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Spacer(Modifier.size(8.dp))
                confirm.children.mapNotNull { CauldronUi.node(it) }.forEach { ButtonRow(it) }
            }
        }
    }
}

@Composable
internal fun SearchField(node: UiNode) {
    if (!node.props.containsKey("search")) return
    var text by remember { mutableStateOf(node.string("search") ?: "") }
    OutlinedTextField(
        value = text,
        onValueChange = {
            text = it
            UiEvents(node.id).send("search", it)
        },
        placeholder = { Text(node.string("search_prompt") ?: "Search") },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
    )
}
