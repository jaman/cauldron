package cauldron.app

import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.HapticFeedbackConstants
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

object CauldronDevice {
    private val main = Handler(Looper.getMainLooper())
    private val keys = AtomicInteger()
    private var recording: Pair<String, File>? = null
    private var recorder: MediaRecorder? = null
    private var player: Player? = null
    private var playing: String? = null

    private val permissions = mapOf(
        "camera" to listOf("android.permission.CAMERA"),
        "microphone" to listOf("android.permission.RECORD_AUDIO"),
        "photos" to emptyList(),
        "location" to listOf("android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION"),
        "notifications" to listOf("android.permission.POST_NOTIFICATIONS")
    )

    @JvmStatic
    fun request(json: ByteArray) {
        val request = JSONObject(String(json, Charsets.UTF_8))
        main.post { handle(request) }
    }

    @Volatile var context: Context? = null

    private fun handle(request: JSONObject) {
        val app = context ?: return answer(request, "error", "no_activity")
        when (request.getString("action")) {
            "weather" -> CauldronWeather.current(request)
            "background_schedule" -> CauldronBackground.schedule(app, request)
            "background_done" -> CauldronBackground.done()
            "background_cancel" -> CauldronBackground.cancel(app)
            "notify" -> CauldronNotifications.schedule(app, CauldronActivity.current, request)
            "notify_cancel" -> CauldronNotifications.cancel(app, request.getString("id"))
            "widget_update" -> CauldronWidgets.update(app, request)
            "activity_start" -> CauldronLiveUpdates.start(app, CauldronActivity.current, request)
            "activity_update" -> CauldronLiveUpdates.update(app, request)
            "activity_finish" -> CauldronLiveUpdates.finish(app, request)
            "purchase_products" -> CauldronPurchases.products(app, request.getString("id"), strings(request.optJSONArray("keys")))
            "purchase_buy" -> CauldronPurchases.buy(app, CauldronActivity.current, request.getString("id"), request.getString("key"))
            "purchase_owned", "purchase_restore" -> CauldronPurchases.owned(app, request.getString("id"))
            "purchase_watch" -> CauldronPurchases.watch(app, request.getString("id"))
            "purchase_subscription" -> CauldronPurchases.subscription(app, request.getString("id"), strings(request.optJSONArray("keys")))
            "purchase_transactions" -> CauldronPurchases.transactions(app, request.getString("id"))
            "purchase_refund" -> answer(request.getString("id"), "error", "unsupported")
            "purchase_manage" -> CauldronPurchases.manage(app)
            "purchase_redeem" -> CauldronPurchases.redeem(app, request.getString("id"))
            "request_review" -> CauldronReview.request(CauldronActivity.current)
            else -> withActivity(request)
        }
    }

    private fun withActivity(request: JSONObject) {
        val activity = CauldronActivity.current ?: return answer(request, "error", "no_activity")
        when (request.getString("action")) {
            "haptic" -> haptic(activity, request.getString("style"))
            "pick_photos" -> pickPhotos(activity, request)
            "take_photo" -> capture(activity, request, ActivityResultContracts.TakePicture(), "jpg", listOf("camera"))
            "record_video" -> capture(activity, request, ActivityResultContracts.CaptureVideo(), "mp4", listOf("camera", "microphone"))
            "pick_files" -> pickFiles(activity, request)
            "permission" -> permission(activity, request)
            "record_start" -> startRecording(activity, request)
            "record_stop" -> stopRecording()
            "share" -> share(activity, request)
            "open_url" -> activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(request.getString("url"))))
            "play" -> play(activity, request)
            "playback" -> playback(request.getString("command"))
            "location" -> CauldronLocation.current(activity, request)
            "location_watch" -> CauldronLocation.watch(activity, request)
            "location_stop" -> CauldronLocation.stop(activity)
            "push_register" -> CauldronPush.register(activity, request.getString("id"))
        }
    }

    private fun haptic(activity: CauldronActivity, style: String) {
        val feedback = when (style) {
            "selection" -> HapticFeedbackConstants.CLOCK_TICK
            "light", "soft" -> HapticFeedbackConstants.KEYBOARD_TAP
            "medium", "rigid" -> HapticFeedbackConstants.CONTEXT_CLICK
            "heavy", "warning" -> HapticFeedbackConstants.LONG_PRESS
            "success" -> HapticFeedbackConstants.CONFIRM
            "error" -> HapticFeedbackConstants.REJECT
            else -> HapticFeedbackConstants.KEYBOARD_TAP
        }
        activity.window.decorView.performHapticFeedback(feedback)
    }

    internal fun <I, O> launch(activity: CauldronActivity, contract: ActivityResultContract<I, O>, input: I, done: (O) -> Unit) {
        var launcher: ActivityResultLauncher<I>? = null
        launcher = activity.activityResultRegistry.register("cauldron-${keys.incrementAndGet()}", contract) { output ->
            launcher?.unregister()
            done(output)
        }
        launcher.launch(input)
    }

    private fun pickPhotos(activity: CauldronActivity, request: JSONObject) {
        val kind = if (request.optBoolean("videos")) ActivityResultContracts.PickVisualMedia.ImageAndVideo else ActivityResultContracts.PickVisualMedia.ImageOnly
        val media = PickVisualMediaRequest.Builder().setMediaType(kind).build()
        val limit = request.optInt("limit", 1)
        if (limit == 1) {
            launch(activity, ActivityResultContracts.PickVisualMedia(), media) { uri ->
                if (uri == null) answer(request, "cancelled", null) else answer(request, "ok", JSONArray(listOf(copied(activity, uri, "picked"))))
            }
        } else {
            val contract = if (limit > 1) ActivityResultContracts.PickMultipleVisualMedia(limit) else ActivityResultContracts.PickMultipleVisualMedia()
            launch(activity, contract, media) { uris ->
                if (uris.isEmpty()) answer(request, "cancelled", null) else answer(request, "ok", JSONArray(uris.map { copied(activity, it, "picked") }))
            }
        }
    }

    private fun capture(activity: CauldronActivity, request: JSONObject, contract: ActivityResultContract<Uri, Boolean>, extension: String, needs: List<String>) {
        val missing = needs.firstOrNull { !declared(activity, it) }
        if (missing != null) return answer(request, "error", "not_declared")
        val file = File(activity.cacheDir, "captures/capture-${System.currentTimeMillis()}.$extension")
        file.parentFile?.mkdirs()
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
        launch(activity, contract, uri) { saved ->
            if (saved == true && file.length() > 0) answer(request, "ok", file.absolutePath) else answer(request, "cancelled", null)
        }
    }

    private fun pickFiles(activity: CauldronActivity, request: JSONObject) {
        val types = request.optJSONArray("types") ?: JSONArray(listOf("any"))
        val mimes = (0 until types.length()).map { mime(types.getString(it)) }.toTypedArray()
        if (request.optBoolean("many")) {
            launch(activity, ActivityResultContracts.OpenMultipleDocuments(), mimes) { uris ->
                if (uris.isEmpty()) answer(request, "cancelled", null) else answer(request, "ok", JSONArray(uris.map { copied(activity, it, "files") }))
            }
        } else {
            launch(activity, ActivityResultContracts.OpenDocument(), mimes) { uri ->
                if (uri == null) answer(request, "cancelled", null) else answer(request, "ok", JSONArray(listOf(copied(activity, uri, "files"))))
            }
        }
    }

    private fun mime(type: String): String = when (type) {
        "image" -> "image/*"
        "video" -> "video/*"
        "audio" -> "audio/*"
        "pdf" -> "application/pdf"
        "text" -> "text/*"
        else -> "*/*"
    }

    private fun copied(activity: CauldronActivity, uri: Uri, folder: String): String {
        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: "file-${System.currentTimeMillis()}"
        val file = File(activity.cacheDir, "$folder/${System.nanoTime()}-$name")
        file.parentFile?.mkdirs()
        activity.contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } }
        return file.absolutePath
    }

    internal fun declared(context: Context, name: String): Boolean {
        val needed = permissions[name] ?: return false
        if (needed.isEmpty()) return true
        val requested = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions?.toSet() ?: emptySet()
        return needed.all { it in requested }
    }

    private fun permission(activity: CauldronActivity, request: JSONObject) {
        val name = request.getString("name")
        if (!declared(activity, name)) return answer(request, "error", "not_declared")
        val needed = permissions[name] ?: emptyList()
        if (needed.isEmpty()) return answer(request, "ok", "granted")
        launch(activity, ActivityResultContracts.RequestMultiplePermissions(), needed.toTypedArray()) { result ->
            answer(request, "ok", if (result.values.any { it }) "granted" else "denied")
        }
    }

    private fun startRecording(activity: CauldronActivity, request: JSONObject) {
        if (!declared(activity, "microphone")) return answer(request, "error", "not_declared")
        if (activity.checkSelfPermission("android.permission.RECORD_AUDIO") != PackageManager.PERMISSION_GRANTED) return answer(request, "error", "denied")
        val file = File(activity.cacheDir, "recordings/recording-${System.currentTimeMillis()}.m4a")
        file.parentFile?.mkdirs()
        recorder = MediaRecorder(activity).apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        recording = request.getString("id") to file
    }

    private fun stopRecording() {
        val (id, file) = recording ?: return
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        recording = null
        answer(id, "ok", file.absolutePath)
    }

    private fun share(activity: CauldronActivity, request: JSONObject) {
        val intent = Intent(Intent.ACTION_SEND)
        val path = request.optString("file", "")
        if (path.isNotEmpty()) {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", File(path))
            intent.type = activity.contentResolver.getType(uri) ?: "*/*"
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            intent.type = "text/plain"
            intent.putExtra(Intent.EXTRA_TEXT, request.optString("text"))
        }
        activity.startActivity(Intent.createChooser(intent, null))
    }

    private fun play(activity: CauldronActivity, request: JSONObject) {
        val item = MediaItem.Builder()
            .setUri(source(request.getString("source")))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(request.optString("title")).setArtist(request.optString("artist")).build())
            .build()
        playing = request.getString("id")
        withPlayer(activity) { player ->
            player.setMediaItem(item)
            player.prepare()
            player.play()
        }
    }

    private fun withPlayer(activity: CauldronActivity, use: (Player) -> Unit) {
        player?.let { return use(it) }
        val service = ComponentName(activity, CauldronPlayback::class.java)
        val declared = runCatching { activity.packageManager.getServiceInfo(service, 0) }.isSuccess
        if (declared) {
            val future = MediaController.Builder(activity, SessionToken(activity, service)).buildAsync()
            future.addListener({ attach(future.get()).also(use) }, { main.post(it) })
        } else {
            use(attach(ExoPlayer.Builder(activity).build()))
        }
    }

    private fun attach(created: Player): Player {
        created.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) playing?.let { answer(it, "ok", "finished") }
            }
        })
        player = created
        return created
    }

    private fun playback(action: String) {
        val current = player ?: return
        when (action) {
            "pause" -> current.pause()
            "resume" -> current.play()
            "stop" -> current.stop()
        }
    }

    internal fun source(text: String): Uri =
        if (text.startsWith("http://") || text.startsWith("https://")) Uri.parse(text) else Uri.fromFile(File(text))

    private fun answer(request: JSONObject, status: String, value: Any?) = answer(request.getString("id"), status, value)

    private fun strings(array: JSONArray?): List<String> = if (array == null) emptyList() else List(array.length()) { array.getString(it) }

    internal fun onMain(block: () -> Unit) {
        main.post(block)
    }

    internal fun answer(id: String, status: String, value: Any?) {
        val message = JSONObject().put("id", id).put("status", status)
        if (value != null) message.put("value", value)
        CauldronActivity.result(message.toString().toByteArray(Charsets.UTF_8))
    }
}

class CauldronPlayback : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        session = MediaSession.Builder(this, ExoPlayer.Builder(this).build()).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }
}
