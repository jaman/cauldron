package cauldron.app

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.res.painterResource

object CauldronAssets {
    fun resourceName(name: String): String =
        "asset_" + name.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')

    @SuppressLint("DiscouragedApi")
    fun drawable(context: Context, name: String): Int =
        context.resources.getIdentifier(resourceName(name), "drawable", context.packageName)

    @SuppressLint("DiscouragedApi")
    fun colour(context: Context, name: String): Int =
        context.resources.getIdentifier(resourceName(name), "color", context.packageName)

    fun vector(context: Context, id: Int): Boolean {
        val value = TypedValue()
        context.resources.getValue(id, value, true)
        return value.string?.endsWith(".xml") == true
    }
}

@Composable
fun cauldronAsset(name: String): Int = CauldronAssets.drawable(LocalContext.current, name)

@Composable
fun cauldronAssetColour(name: String): Color {
    val id = CauldronAssets.colour(LocalContext.current, name)
    return if (id == 0) Color.Unspecified else colorResource(id)
}

@Composable
internal fun NodeGlyph(node: UiNode, name: String?, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) {
    val id = node.string("asset")?.let { cauldronAsset(it) } ?: 0
    if (id != 0) Icon(painterResource(id), contentDescription = null, tint = tint, modifier = modifier)
    else Icon(iconFor(name, node.string("android")), contentDescription = null, tint = tint, modifier = modifier)
}
