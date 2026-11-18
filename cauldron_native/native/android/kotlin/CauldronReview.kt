package cauldron.app

import com.google.android.play.core.review.ReviewManagerFactory

/** `CauldronNative.Device.request_review/0` on Android: Google Play's in-app review. */
object CauldronReview {
    fun request(activity: CauldronActivity?) {
        val shown = activity ?: return
        val manager = ReviewManagerFactory.create(shown)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (request.isSuccessful) manager.launchReviewFlow(shown, request.result)
        }
    }
}
