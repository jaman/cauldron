package cauldron.app

import android.content.pm.PackageManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

@Composable
internal fun NodeVideo(node: UiNode, modifier: Modifier) {
    val context = LocalContext.current
    val source = node.string("source") ?: ""
    val events = UiEvents(node.id)
    val player = remember(source) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(CauldronDevice.source(source)))
            prepare()
        }
    }
    player.repeatMode = if (node.bool("loop")) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    player.volume = if (node.bool("muted")) 0f else 1f
    DisposableEffect(player) {
        val ended = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) events.send("end")
            }
        }
        player.addListener(ended)
        player.playWhenReady = node.bool("autoplay")
        onDispose {
            player.removeListener(ended)
            player.release()
        }
    }
    val controls = node.props["controls"] as? Boolean ?: true
    AndroidView(
        factory = { PlayerView(it).apply { this.player = player } },
        update = { view ->
            view.player = player
            view.useController = controls
        },
        modifier = modifier.fillMaxWidth().aspectRatio(16f / 9f)
    )
}

@Composable
internal fun NodeCameraPreview(node: UiNode, modifier: Modifier) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var granted by remember { mutableStateOf(cameraGranted(context)) }
    LifecycleResumeEffect(Unit) {
        granted = cameraGranted(context)
        onPauseOrDispose {}
    }
    val selector = if (node.string("facing") == "front") CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
    if (!granted) {
        Box(modifier = modifier.fillMaxWidth().aspectRatio(3f / 4f), contentAlignment = Alignment.Center) {
            Text("No access to the camera", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    val view = remember { PreviewView(context).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE } }
    DisposableEffect(selector, owner) {
        val future = ProcessCameraProvider.getInstance(context)
        val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
        future.addListener({
            val provider = future.get()
            provider.unbindAll()
            runCatching { provider.bindToLifecycle(owner, selector, preview) }
        }, ContextCompat.getMainExecutor(context))
        onDispose { if (future.isDone) future.get().unbind(preview) }
    }
    AndroidView(factory = { view }, modifier = modifier.fillMaxWidth().aspectRatio(3f / 4f))
}

private fun cameraGranted(context: android.content.Context): Boolean =
    ContextCompat.checkSelfPermission(context, "android.permission.CAMERA") == PackageManager.PERMISSION_GRANTED
