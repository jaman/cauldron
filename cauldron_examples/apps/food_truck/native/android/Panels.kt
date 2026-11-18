package foodtruck

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.SentimentSatisfied
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cauldron.app.CauldronMapView
import cauldron.app.CauldronNativeView
import cauldron.app.UiEvents
import cauldron.app.UiNode
import cauldron.app.cauldronAsset

private val plusGradient = Brush.verticalGradient(listOf(Color(0xFF6E6CE0), Color(0xFF5856D6)))

object SpotShowcaseView : CauldronNativeView {
    override val name = "spot_showcase"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        var seconds by remember { mutableFloatStateOf(0f) }
        LaunchedEffect(Unit) {
            while (true) withFrameNanos { seconds = (System.currentTimeMillis() % 3_600_000L) / 1000f }
        }
        val heading = (seconds % 240f) / 240f * 360f
        val swing = (seconds % 60f) / 60f
        val folded = if (swing <= 0.5f) swing * 2 else 2 - swing * 2
        val eased = folded * folded * (3 - 2 * folded)
        CauldronMapView(
            node.double("latitude") ?: 0.0,
            node.double("longitude") ?: 0.0,
            node.double("distance") ?: 1000.0,
            50f + 10f * eased,
            heading,
            Modifier.fillMaxSize()
        )
    }
}

object FlavorProfileView : CauldronNativeView {
    override val name = "flavor_profile"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val flavors = (node.props["flavors"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
        val top = (node.double("top") ?: 1.0).coerceAtLeast(1.0).toFloat()
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (flavor in flavors) {
                val strongest = flavor["strongest"] == true
                val value = ((flavor["value"] as? Number)?.toFloat() ?: 0f).coerceAtLeast(0f)
                val tone = if (strongest) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val asset = flavor["asset"] as? String
                    val id = asset?.let { cauldronAsset(it) } ?: 0
                    if (id != 0) Icon(painterResource(id), null, tint = tone, modifier = Modifier.size(18.dp))
                    else Icon(Icons.Outlined.SentimentSatisfied, null, tint = tone, modifier = Modifier.size(18.dp))
                    Text(flavor["title"]?.toString() ?: "", color = tone, modifier = Modifier.padding(start = 8.dp).widthIn(min = 64.dp))
                    LinearProgressIndicator(
                        progress = { value / top },
                        color = if (strongest) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp)
                    )
                    Text(value.toInt().toString(), color = tone)
                }
            }
        }
    }
}

object PlusMarketingView : CauldronNativeView {
    override val name = "plus_marketing"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        Column(
            Modifier.fillMaxWidth().background(plusGradient, RoundedCornerShape(16.dp)).padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text("Get Social Feed+", color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("The definitive social-feed experience", color = Color.White, style = MaterialTheme.typography.bodyMedium)
            Button(
                onClick = { events.send("start") },
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color(0xFF5856D6)),
                modifier = Modifier.padding(top = 12.dp)
            ) { Text("Get Started", fontWeight = FontWeight.Bold) }
        }
    }
}

object SubscriptionStoreView : CauldronNativeView {
    override val name = "subscription_store"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val plans = (node.props["plans"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
        var chosen by remember(plans.size) { mutableStateOf(plans.firstOrNull()?.get("key")?.toString()) }
        val plan = plans.firstOrNull { it["key"]?.toString() == chosen }
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer)) {
            Box(Modifier.fillMaxWidth().background(plusGradient)) {
                Column(Modifier.fillMaxWidth().padding(top = 24.dp, bottom = 30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Social Feed+", color = Color.White, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, modifier = Modifier.padding(16.dp))
                    for (line in listOf("Top social-media providers.", "Advanced engagement tools.", "All in one place.")) {
                        Text(line, color = Color.White, style = MaterialTheme.typography.titleMedium)
                    }
                }
                IconButton(onClick = { events.send("close") }, modifier = Modifier.align(Alignment.TopEnd)) {
                    Icon(Icons.Filled.Close, "Close", tint = Color.White.copy(alpha = 0.8f))
                }
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 16.dp)) {
                for (option in plans) PlanCard(option, option["key"]?.toString() == chosen) { chosen = it }
                (node.string("note"))?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp)) }
            }
            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Button(onClick = { chosen?.let { events.send("subscribe", it) } }, enabled = plan != null, modifier = Modifier.fillMaxWidth()) {
                    Text(if (plan?.get("intro") == true) "Start trial offer" else "Subscribe", fontWeight = FontWeight.Bold)
                }
                TextButton(onClick = { events.send("redeem") }) { Text("Redeem an offer") }
            }
        }
    }

    @Composable
    private fun PlanCard(plan: Map<*, *>, on: Boolean, choose: (String?) -> Unit) {
        val key = plan["key"]?.toString()
        Card(
            onClick = { choose(if (on) null else key) },
            shape = RoundedCornerShape(16.dp),
            border = if (on) BorderStroke(1.dp, MaterialTheme.colorScheme.primary) else null,
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 5.dp)
        ) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(plan["name"]?.toString() ?: "", style = MaterialTheme.typography.titleMedium)
                    Text(plan["description"]?.toString() ?: "", modifier = Modifier.padding(bottom = 2.dp))
                    Text(plan["price"]?.toString() ?: "")
                    (plan["savings"] as? String)?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
                }
                Icon(
                    if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    null,
                    tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                )
            }
        }
    }
}

object UnlockFeatureView : CauldronNativeView {
    override val name = "unlock_feature"

    @Composable
    override fun Content(node: UiNode, events: UiEvents) {
        val name = (node.string("name") ?: "").lowercase()
        val price = node.string("price") ?: ""
        val shape = RoundedCornerShape(15.dp)
        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.widthIn(max = 400.dp).fillMaxWidth().shadow(10.dp, shape).background(MaterialTheme.colorScheme.surface, shape)) {
                if (node.bool("expanded")) {
                    Column(Modifier.fillMaxWidth().padding(top = 46.dp, start = 16.dp, end = 16.dp, bottom = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(15.dp)) {
                        Text("Unlock a $name for only $price", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                        Text("Get the full picture with data and insights that cover an entire year.", style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                        Button(onClick = { events.send("unlock") }) { Text("Unlock") }
                    }
                    IconButton(onClick = { events.send("collapse") }, modifier = Modifier.align(Alignment.TopEnd)) {
                        Icon(Icons.Filled.Close, "Dismiss", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    Row(Modifier.fillMaxWidth().clickable { events.send("expand") }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text("Unlock a $name", fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                            Text("for only $price", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Button(onClick = { events.send("unlock") }) { Text("Unlock") }
                    }
                }
            }
        }
    }
}

