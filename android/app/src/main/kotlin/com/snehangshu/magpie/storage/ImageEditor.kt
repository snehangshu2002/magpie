package com.snehangshu.magpie.storage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import com.snehangshu.magpie.engine.FitTooLargeException
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException

/**
 * Makes resized, recompressed or converted copies of images with Android's
 * own codecs. A copy is drawn from the pixels alone, so it carries none of
 * the original's metadata (location, camera).
 */
object ImageEditor {
    /** `{width, height}` of the image at [uri] as it is shown (after its EXIF rotation). */
    fun probe(context: Context, uri: Uri): Map<String, Any?> {
        val bounds = bounds(context, uri)
        val turned = rotationOf(context, uri) % 180 != 0
        return mapOf(
            "width" to if (turned) bounds.outHeight else bounds.outWidth,
            "height" to if (turned) bounds.outWidth else bounds.outHeight,
        )
    }

    /**
     * Writes the image at [uri] to [target], scaled to [width]x[height], as
     * [format] (`jpg`, `png` or `webp`) at [quality]. First it is turned
     * [rotate] degrees clockwise (0, 90, 180 or 270) and cut to [crop]
     * (`left, top, width, height` in the turned image's pixels), when given.
     * With [targetBytes], the quality and then the size in pixels are
     * lowered until the file fits.
     */
    fun edit(
        context: Context,
        uri: Uri,
        target: File,
        format: String,
        width: Int,
        height: Int,
        quality: Int,
        targetBytes: Long?,
        rotate: Int = 0,
        crop: List<Int>? = null,
    ) {
        require(width > 0 && height > 0) { "Bad size: ${width}x$height" }
        var bitmap = load(context, uri, width, height, opaque = format == "jpg", rotate, crop)
        try {
            while (true) {
                val bytes = encodeToFit(bitmap, format, quality.coerceIn(1, 100), targetBytes)
                if (bytes != null) {
                    target.writeBytes(bytes)
                    return
                }
                // Still too big at the lowest quality: fewer pixels.
                val w = bitmap.width * 3 / 4
                val h = bitmap.height * 3 / 4
                if (w < MIN_SIDE || h < MIN_SIDE) {
                    throw FitTooLargeException("Can't get the image under $targetBytes bytes")
                }
                bitmap = Bitmap.createScaledBitmap(bitmap, w, h, true).also {
                    if (it !== bitmap) bitmap.recycle()
                }
            }
        } finally {
            bitmap.recycle()
        }
    }

    /** The image at [uri] upright, at most [maxSide] pixels on its longer side, on white. */
    fun decodeUpright(context: Context, uri: Uri, maxSide: Int): Bitmap {
        val shown = probe(context, uri)
        val width = shown["width"] as Int
        val height = shown["height"] as Int
        val scale = minOf(1.0, maxSide.toDouble() / maxOf(width, height))
        return load(
            context,
            uri,
            (width * scale).toInt().coerceAtLeast(1),
            (height * scale).toInt().coerceAtLeast(1),
            opaque = true,
            rotate = 0,
            crop = null,
        )
    }

    /**
     * The highest quality from [MIN_QUALITY] to [max] that [fits], or null if
     * none does. [fits] must hold for every quality below one that fits.
     */
    fun bestQuality(max: Int, fits: (Int) -> Boolean): Int? {
        if (fits(max)) return max
        var low = MIN_QUALITY
        if (max <= low || !fits(low)) return null
        var high = max // fits(low), !fits(high)
        while (high - low > 1) {
            val mid = (low + high) / 2
            if (fits(mid)) low = mid else high = mid
        }
        return low
    }

    private fun encodeToFit(bitmap: Bitmap, format: String, quality: Int, targetBytes: Long?): ByteArray? {
        if (targetBytes == null) return encode(bitmap, format, quality)
        // PNG is lossless: quality changes nothing, only fewer pixels help.
        if (format == "png") return encode(bitmap, format, quality).takeIf { it.size <= targetBytes }
        var best: ByteArray? = null
        bestQuality(quality) { q ->
            val bytes = encode(bitmap, format, q)
            (bytes.size <= targetBytes).also { if (it) best = bytes }
        }
        return best
    }

    private fun encode(bitmap: Bitmap, format: String, quality: Int): ByteArray {
        @Suppress("DEPRECATION")
        val codec = when (format) {
            "jpg" -> Bitmap.CompressFormat.JPEG
            "png" -> Bitmap.CompressFormat.PNG
            "webp" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                Bitmap.CompressFormat.WEBP
            }
            else -> throw IllegalArgumentException("Unknown format: $format")
        }
        return ByteArrayOutputStream().use { out ->
            if (!bitmap.compress(codec, quality, out)) throw StorageException("Couldn't encode the image")
            out.toByteArray()
        }
    }

    /**
     * The image upright, turned [rotate] more degrees, cut to [crop] and
     * scaled to [width]x[height]; on white when [opaque] (JPEG has no
     * transparency).
     */
    private fun load(
        context: Context,
        uri: Uri,
        width: Int,
        height: Int,
        opaque: Boolean,
        rotate: Int,
        crop: List<Int>?,
    ): Bitmap {
        val bounds = bounds(context, uri)
        val rotation = (rotationOf(context, uri) + rotate) % 360
        val turned = rotation % 180 != 0
        // The whole picture as it will be shown, in the file's pixels.
        val fullWidth = if (turned) bounds.outHeight else bounds.outWidth
        val fullHeight = if (turned) bounds.outWidth else bounds.outHeight
        val (left, top, cropWidth, cropHeight) = crop ?: listOf(0, 0, fullWidth, fullHeight)
        require(cropWidth > 0 && cropHeight > 0 && left >= 0 && top >= 0 &&
            left + cropWidth <= fullWidth && top + cropHeight <= fullHeight) { "Bad crop: $crop" }
        // Decode at a fraction when the copy is much smaller, to save memory.
        var sample = 1
        while (cropWidth / (sample * 2) >= width && cropHeight / (sample * 2) >= height) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = try {
            open(context, uri).use { BitmapFactory.decodeStream(it, null, options) }
        } catch (e: OutOfMemoryError) {
            throw StorageException("The image is too big to edit", e)
        } ?: throw StorageException("Couldn't read the image at $uri")

        val result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        if (opaque) canvas.drawColor(Color.WHITE)
        // Decoded pixels per pixel of the file (about 1 / sample).
        val shrink = decoded.width.toFloat() / bounds.outWidth
        val matrix = Matrix().apply {
            postTranslate(-decoded.width / 2f, -decoded.height / 2f)
            postRotate(rotation.toFloat())
            postTranslate(fullWidth * shrink / 2f, fullHeight * shrink / 2f)
            postTranslate(-left * shrink, -top * shrink)
            postScale(width / (cropWidth * shrink), height / (cropHeight * shrink))
        }
        canvas.drawBitmap(decoded, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
        decoded.recycle()
        return result
    }

    private fun bounds(context: Context, uri: Uri): BitmapFactory.Options {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open(context, uri).use { BitmapFactory.decodeStream(it, null, options) }
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            throw StorageException("Couldn't read the image at $uri")
        }
        return options
    }

    /** Degrees clockwise the stored pixels must be turned to show upright. Mirrored images are rare; not handled. */
    private fun rotationOf(context: Context, uri: Uri): Int = try {
        open(context, uri).use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0)) {
                ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSPOSE -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSVERSE -> 270
                else -> 0
            }
        }
    } catch (e: FileNotFoundException) {
        throw e
    } catch (_: Exception) {
        0 // No readable EXIF (PNG, WebP without it): upright as stored.
    }

    private fun open(context: Context, uri: Uri) = try {
        context.contentResolver.openInputStream(uri)
    } catch (e: SecurityException) {
        throw StorageException("Not allowed to read $uri", e)
    } ?: throw FileNotFoundException(uri.toString())

    const val MIN_QUALITY = 10
    private const val MIN_SIDE = 16
}
