package cauldron.app

import android.graphics.Rect
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlinx.coroutines.launch

/**
 * Reports how a foldable is folded to the app as `{:cauldron_native, :posture, ...}`: the
 * fold that crosses the window from Jetpack WindowManager, and the hinge's angle from the
 * hinge angle sensor. A device with neither reports nothing.
 */
object CauldronFold : SensorEventListener {
    private const val CLOSED_WITHIN = 10f
    private const val UNKNOWN = 0
    private const val CLOSED = 1
    private const val HALF_OPEN = 2
    private const val OPEN = 3

    private var feature: FoldingFeature? = null
    private var angle: Float? = null
    private var foldable = false
    private var reported: Posture? = null

    @JvmStatic
    fun watch(activity: ComponentActivity) {
        val sensors = activity.getSystemService(SensorManager::class.java)
        val hinge = sensors?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
        if (hinge != null) foldable = true
        activity.lifecycleScope.launch {
            activity.repeatOnLifecycle(Lifecycle.State.STARTED) {
                if (hinge != null) sensors.registerListener(this@CauldronFold, hinge, SensorManager.SENSOR_DELAY_UI)
                try {
                    WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity).collect { info ->
                        feature = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
                        if (feature != null) foldable = true
                        report()
                    }
                } finally {
                    sensors?.unregisterListener(this@CauldronFold)
                }
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        angle = event.values[0]
        report()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private data class Posture(
        val fold: Int, val angle: Float?, val hinge: Rect?, val vertical: Boolean, val separating: Boolean
    )

    private fun report() {
        if (!foldable) return
        val shown = feature
        val posture = Posture(
            fold(shown), angle, shown?.bounds,
            shown?.orientation == FoldingFeature.Orientation.VERTICAL, shown?.isSeparating ?: false
        )
        if (posture == reported) return
        reported = posture
        val hinge = posture.hinge ?: Rect()
        CauldronActivity.posture(
            posture.fold, posture.angle != null, posture.angle ?: 0f, posture.hinge != null,
            hinge.left, hinge.top, hinge.width(), hinge.height(), posture.vertical, posture.separating
        )
    }

    private fun fold(shown: FoldingFeature?): Int = when {
        shown?.state == FoldingFeature.State.HALF_OPENED -> HALF_OPEN
        shown?.state == FoldingFeature.State.FLAT -> OPEN
        angle?.let { it <= CLOSED_WITHIN } == true -> CLOSED
        else -> UNKNOWN
    }
}
