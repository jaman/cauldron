package cauldron.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.graphics.vector.toPath

/**
 * Material icons drawn into bitmaps, for the places outside Compose that take an image:
 * notification icons and Glance widgets. Names are as `iconFor` takes them.
 */
internal object CauldronIcons {
    fun bitmap(name: String?, own: String?, size: Int, color: Int = Color.WHITE): Bitmap {
        val vector = iconFor(name, own)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(size / vector.viewportWidth, size / vector.viewportHeight)
        draw(vector.root, canvas, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
        return bitmap
    }

    private fun draw(group: VectorGroup, canvas: Canvas, paint: Paint) {
        canvas.save()
        canvas.translate(group.translationX + group.pivotX, group.translationY + group.pivotY)
        canvas.rotate(group.rotation)
        canvas.scale(group.scaleX, group.scaleY)
        canvas.translate(-group.pivotX, -group.pivotY)
        for (node in group) {
            when (node) {
                is VectorPath -> canvas.drawPath(path(node), paint.apply { alpha = (node.fillAlpha * 255).toInt() })
                is VectorGroup -> draw(node, canvas, paint)
            }
        }
        canvas.restore()
    }

    private fun path(node: VectorPath): Path = node.pathData.toPath().asAndroidPath().apply {
        fillType = if (node.pathFillType == PathFillType.EvenOdd) Path.FillType.EVEN_ODD else Path.FillType.WINDING
    }
}
