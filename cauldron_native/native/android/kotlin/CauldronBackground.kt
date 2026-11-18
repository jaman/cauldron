package cauldron.app

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * `CauldronNative.Background` on Android: a periodic WorkManager job that starts the BEAM
 * if the app is not running, tells the app to refresh, and waits for its `done`.
 */
object CauldronBackground {
    private const val WORK = "cauldron.refresh"
    @Volatile private var waiting: CountDownLatch? = null

    fun schedule(context: Context, request: JSONObject) {
        val minutes = request.optLong("minutes", 15).coerceAtLeast(15)
        val work = PeriodicWorkRequestBuilder<CauldronRefreshWorker>(minutes, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, work)
        CauldronDevice.answer(request.getString("id"), "ok", "scheduled")
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK)
    }

    fun done() {
        waiting?.countDown()
    }

    internal fun refresh(context: Context): Boolean {
        val latch = CountDownLatch(1)
        waiting = latch
        CauldronActivity.startBeam(context)
        CauldronActivity.background()
        return latch.await(25, TimeUnit.SECONDS)
    }
}

class CauldronRefreshWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result =
        if (CauldronBackground.refresh(applicationContext)) Result.success() else Result.retry()
}
