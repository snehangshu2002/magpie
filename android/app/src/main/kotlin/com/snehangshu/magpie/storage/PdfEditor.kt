package com.snehangshu.magpie.storage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.PDResources
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.color.PDColor
import com.tom_roush.pdfbox.pdmodel.graphics.color.PDDeviceRGB
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.util.Matrix
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** The PDF needs a password, or the one given is wrong; reported as `PROTECTED`. */
class PdfProtectedException(message: String, cause: Throwable? = null) : IOException(message, cause)

/** The font can't write some of the text (e.g. a script it has no letters for); `UNSUPPORTED_TEXT`. */
class UnsupportedTextException(message: String, cause: Throwable? = null) : IOException(message, cause)

/** What an `editPdf` call asks for; Dart decides every value (see CLAUDE.md). */
data class PdfJob(
    val op: String,
    val uris: List<Uri>,
    /** File name of the result without extension; `<name> <n>` for several. */
    val name: String,
    /** 1-based pages, in order: kept by `extract`, turned by `rotate`, written on by `addText`; null is all. */
    val pages: List<Int>? = null,
    val degrees: Int = 90,
    val text: String = "",
    /** `topLeft` … `bottomRight`, or `center`. */
    val place: String = "bottomCenter",
    val fontSize: Float = 12f,
    /** 0–1. */
    val opacity: Float = 1f,
    /** Written large, across the page: a watermark. */
    val diagonal: Boolean = false,
    val password: String? = null,
    /** JPEG quality 1–100 for `compress`, `fromImages` and `toImages`. */
    val quality: Int = 80,
    /** Longest side in pixels of a picture `compress` or `fromImages` keeps. */
    val maxSide: Int = 2000,
    /** `a4` puts each photo on an A4 page; `fit` makes the page the photo's size. */
    val pageSize: String = "fit",
)

/**
 * Edits PDFs with pdfbox-android (merge, pages, text, passwords, smaller
 * pictures) and Android's own PdfRenderer (pages as photos). Works on files
 * copied into [workDir]; returns the result files there, in order.
 */
internal class PdfEditor(private val context: Context, private val workDir: File) {

    init {
        PDFBoxResourceLoader.init(context.applicationContext)
    }

    fun run(job: PdfJob): List<File> = try {
        when (job.op) {
            "fromImages" -> listOf(fromImages(job))
            "merge" -> listOf(merge(job))
            "compress" -> listOfNotNull(compress(job))
            "extract" -> listOf(edit(job) { doc -> extract(doc, job.pages.orEmpty()) })
            "rotate" -> listOf(edit(job) { doc -> rotate(doc, job.pages, job.degrees) })
            "addText" -> listOf(edit(job) { doc -> addText(doc, job) })
            "protect" -> listOf(edit(job) { doc -> protect(doc, job.password.orEmpty()) })
            "unlock" -> listOf(edit(job) { doc -> doc.isAllSecurityToBeRemoved = true; doc })
            "toImages" -> toImages(job)
            else -> throw IllegalArgumentException("Unknown op: ${job.op}")
        }
    } catch (e: OutOfMemoryError) {
        throw StorageException("The file is too big to edit", e)
    }

    /** `{pages?, name?, size?, protected}`; `pages` is null when it needs a password. */
    fun info(uri: Uri, password: String?): Map<String, Any?> {
        val (name, size) = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) it.getString(0) to it.getLong(1) else null } ?: (null to null)
        val pages = try {
            load(copyIn(uri, "info.pdf"), password).use { it.numberOfPages }
        } catch (_: PdfProtectedException) {
            null
        }
        return mapOf("pages" to pages, "name" to name, "size" to size, "protected" to (pages == null))
    }

    private fun fromImages(job: PdfJob): File = PDDocument(MemoryUsageSetting.setupTempFileOnly()).use { doc ->
        for (uri in job.uris) {
            val bitmap = ImageEditor.decodeUpright(context, uri, job.maxSide)
            // Drawn on white; without this JPEGFactory adds a needless alpha mask.
            bitmap.setHasAlpha(false)
            try {
                val image = JPEGFactory.createFromImage(doc, bitmap, job.quality / 100f)
                // A photo of `maxSide` pixels fills an A4-sized page (about 150 dpi at 2000).
                val photo = PDRectangle(bitmap.width * POINTS_PER_PIXEL, bitmap.height * POINTS_PER_PIXEL)
                val page = PDPage(if (job.pageSize == "a4") PDRectangle.A4 else photo)
                doc.addPage(page)
                val box = page.mediaBox
                val margin = if (job.pageSize == "a4") A4_MARGIN else 0f
                val scale = min((box.width - 2 * margin) / bitmap.width, (box.height - 2 * margin) / bitmap.height)
                val w = bitmap.width * scale
                val h = bitmap.height * scale
                PDPageContentStream(doc, page).use {
                    it.drawImage(image, (box.width - w) / 2, (box.height - h) / 2, w, h)
                }
            } finally {
                bitmap.recycle()
            }
        }
        output(job).also { doc.save(it) }
    }

    private fun merge(job: PdfJob): File {
        val out = output(job)
        PDFMergerUtility().apply {
            job.uris.forEachIndexed { i, uri ->
                val file = copyIn(uri, "in$i.pdf")
                // Fails here, not halfway, on a PDF that needs a password or
                // has restrictions; the merged copy couldn't keep either.
                load(file, null).use {
                    if (it.isEncrypted) throw PdfProtectedException("Can't merge a protected PDF")
                }
                addSource(file)
            }
            destinationFileName = out.absolutePath
            mergeDocuments(MemoryUsageSetting.setupTempFileOnly())
        }
        return out
    }

    /**
     * Saves the pictures inside again as smaller JPEGs. Null when the
     * result isn't smaller than the original, which is then left alone.
     */
    private fun compress(job: PdfJob): File? {
        val input = copyIn(job.uris.single(), "in.pdf")
        val out = output(job)
        load(input, job.password).use { doc ->
            keepSecurity(doc, job.password)
            val seen = HashSet<Any>()
            for (page in doc.pages) page.resources?.let { shrinkImages(doc, it, job, seen) }
            doc.save(out)
        }
        return out.takeIf { it.length() < input.length() } ?: run { out.delete(); null }
    }

    private fun shrinkImages(doc: PDDocument, resources: PDResources, job: PdfJob, seen: MutableSet<Any>) {
        for (name in resources.xObjectNames.toList()) {
            val xObject = try {
                resources.getXObject(name)
            } catch (_: IOException) {
                continue
            }
            // The same picture on many pages is done once.
            if (!seen.add(xObject.cosObject)) continue
            when (xObject) {
                is PDFormXObject -> xObject.resources?.let { shrinkImages(doc, it, job, seen) }
                is PDImageXObject -> {
                    // Stencils and colour-key masks don't survive as JPEG; leave those.
                    if (xObject.isStencil || xObject.cosObject.containsKey(COSName.MASK)) continue
                    val masked = xObject.softMask != null
                    val bitmap = try {
                        xObject.image
                    } catch (_: Exception) {
                        null // A kind Android can't decode (JPEG 2000): kept as it is.
                    } ?: continue
                    // getImage() applies a soft mask as alpha, which JPEGFactory turns back
                    // into one; an image without one is opaque, so no mask is made for it.
                    if (!masked) bitmap.setHasAlpha(false)
                    val scale = min(1f, job.maxSide.toFloat() / max(bitmap.width, bitmap.height))
                    val smaller = if (scale < 1f) {
                        Bitmap.createScaledBitmap(
                            bitmap,
                            (bitmap.width * scale).roundToInt().coerceAtLeast(1),
                            (bitmap.height * scale).roundToInt().coerceAtLeast(1),
                            true,
                        )
                    } else {
                        bitmap
                    }
                    val replacement = JPEGFactory.createFromImage(doc, smaller, job.quality / 100f)
                    if (smaller !== bitmap) smaller.recycle()
                    bitmap.recycle()
                    if (replacement.cosObject.length < xObject.cosObject.length) {
                        resources.put(name, replacement)
                    }
                }
            }
        }
    }

    /** Keeps only [pages], in their order in the PDF; links and bookmarks to them still work. */
    private fun extract(doc: PDDocument, pages: List<Int>): PDDocument {
        val keep = pages.toSet()
        require(keep.isNotEmpty() && keep.all { it in 1..doc.numberOfPages }) { "Bad pages: $pages" }
        for (p in doc.numberOfPages downTo 1) if (p !in keep) doc.removePage(p - 1)
        return doc
    }

    private fun rotate(doc: PDDocument, pages: List<Int>?, degrees: Int): PDDocument {
        for (p in pages ?: (1..doc.numberOfPages).toList()) {
            val page = doc.getPage(p - 1)
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
        return doc
    }

    /**
     * Writes [PdfJob.text] on the pages, upright as the page is shown.
     * `{n}` and `{total}` become the page's number and the page count.
     */
    private fun addText(doc: PDDocument, job: PdfJob): PDDocument {
        val font = context.assets.open(FONT_ASSET).use { PDType0Font.load(doc, it, true) }
        val total = doc.numberOfPages
        val pages = job.pages ?: (1..total).toList()
        for (p in pages) {
            val page = doc.getPage(p - 1)
            val text = job.text.replace("{n}", "$p").replace("{total}", "$total")
            val width = try {
                font.getStringWidth(text) / 1000 * job.fontSize
            } catch (e: IllegalArgumentException) {
                throw UnsupportedTextException("Can't write: $text", e)
            }
            val box = page.cropBox
            val rotation = ((page.rotation % 360) + 360) % 360
            val turned = rotation % 180 != 0
            // Size of the page as it is shown.
            val pageW = if (turned) box.height else box.width
            val pageH = if (turned) box.width else box.height
            PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { out ->
                // From "as shown" coordinates to the page's own.
                out.transform(
                    when (rotation) {
                        90 -> Matrix(0f, 1f, -1f, 0f, box.upperRightX, box.lowerLeftY)
                        180 -> Matrix(-1f, 0f, 0f, -1f, box.upperRightX, box.upperRightY)
                        270 -> Matrix(0f, -1f, 1f, 0f, box.lowerLeftX, box.upperRightY)
                        else -> Matrix(1f, 0f, 0f, 1f, box.lowerLeftX, box.lowerLeftY)
                    },
                )
                if (job.opacity < 1f) {
                    out.setGraphicsStateParameters(
                        PDExtendedGraphicsState().apply { nonStrokingAlphaConstant = job.opacity },
                    )
                }
                val grey = if (job.diagonal) 0.5f else 0f
                out.setNonStrokingColor(PDColor(floatArrayOf(grey, grey, grey), PDDeviceRGB.INSTANCE))
                out.beginText()
                out.setFont(font, job.fontSize)
                if (job.diagonal) {
                    val angle = Math.atan2(pageH.toDouble(), pageW.toDouble())
                    val cos = Math.cos(angle).toFloat()
                    val sin = Math.sin(angle).toFloat()
                    // Centred on the page, along its diagonal.
                    val x = pageW / 2 - (width / 2) * cos + (job.fontSize / 3) * sin
                    val y = pageH / 2 - (width / 2) * sin - (job.fontSize / 3) * cos
                    out.setTextMatrix(Matrix(cos, sin, -sin, cos, x, y))
                } else {
                    val x = when {
                        job.place.endsWith("Left") -> TEXT_MARGIN
                        job.place.endsWith("Right") -> pageW - TEXT_MARGIN - width
                        else -> (pageW - width) / 2
                    }
                    val y = when {
                        job.place.startsWith("top") -> pageH - TEXT_MARGIN - job.fontSize
                        job.place.startsWith("bottom") -> TEXT_MARGIN
                        else -> (pageH - job.fontSize) / 2
                    }
                    out.newLineAtOffset(x, y)
                }
                out.showText(text)
                out.endText()
            }
        }
        return doc
    }

    private fun protect(doc: PDDocument, password: String): PDDocument {
        require(password.isNotEmpty()) { "Empty password" }
        doc.protect(
            StandardProtectionPolicy(password, password, AccessPermission()).apply { encryptionKeyLength = 256 },
        )
        return doc
    }

    /** Each page as a JPEG, about 150 dpi and at most [MAX_RENDER_SIDE] pixels. */
    private fun toImages(job: PdfJob): List<File> = openRenderer(plainCopy(job.uris.single(), job.password)).use { renderer ->
        List(renderer.pageCount) { i ->
            val bitmap = renderPage(renderer, i) { w, h -> min(RENDER_DPI / 72f, MAX_RENDER_SIDE.toFloat() / max(w, h)) }
            try {
                File(workDir, "${job.name} ${i + 1}.jpg").also { file ->
                    file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, job.quality, it) }
                }
            } finally {
                bitmap.recycle()
            }
        }
    }

    /** A copy of the PDF at [uri] in [workDir] that PdfRenderer can open: PdfRenderer takes no password, so a protected one is saved without security. */
    fun plainCopy(uri: Uri, password: String?): File {
        var input = copyIn(uri, "in.pdf")
        load(input, password).use { doc ->
            if (doc.isEncrypted) {
                doc.isAllSecurityToBeRemoved = true
                input = File(workDir, "plain.pdf").also { doc.save(it) }
            }
        }
        return input
    }

    companion object {
        /** Inter, bundled with the app for its own text: Latin, Greek and Cyrillic. */
        private const val FONT_ASSET = "flutter_assets/assets/fonts/Inter-Regular.ttf"
        private const val POINTS_PER_PIXEL = 72f / 150f
        private const val A4_MARGIN = 28f
        private const val TEXT_MARGIN = 28f
        private const val RENDER_DPI = 150f
        const val MAX_RENDER_SIDE = 2500

        fun openRenderer(file: File): PdfRenderer {
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            return try {
                PdfRenderer(descriptor)
            } catch (e: SecurityException) {
                descriptor.close()
                throw PdfProtectedException("The PDF needs a password", e)
            }
        }

        /** Page [index] on white, [scale] pixels per point (from the page's size in points). */
        fun renderPage(renderer: PdfRenderer, index: Int, scale: (Int, Int) -> Float): Bitmap =
            renderer.openPage(index).use { page ->
                val s = scale(page.width, page.height)
                Bitmap.createBitmap(
                    (page.width * s).roundToInt().coerceAtLeast(1),
                    (page.height * s).roundToInt().coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888,
                ).apply {
                    eraseColor(Color.WHITE)
                    page.render(this, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                }
            }
    }

    /** Loads [PdfJob.uris]'s one PDF, lets [change] return the document to save, and saves it. */
    private fun edit(job: PdfJob, change: (PDDocument) -> PDDocument): File {
        val out = output(job)
        load(copyIn(job.uris.single(), "in.pdf"), job.password).use { doc ->
            val result = change(doc)
            if (job.op != "protect" && job.op != "unlock") keepSecurity(result, job.password)
            try {
                result.save(out)
            } finally {
                if (result !== doc) result.close()
            }
        }
        return out
    }

    /**
     * pdfbox saves a PDF it opened encrypted only with security set again:
     * the copy opens with the same [password] (none for a PDF that only
     * restricts printing or copying) and keeps the same restrictions. The
     * original owner password can't be recovered, so the copy gets
     * [password] or, without one, a random one.
     */
    private fun keepSecurity(doc: PDDocument, password: String?) {
        if (!doc.isEncrypted) return
        val user = password.orEmpty()
        val owner = user.ifEmpty { java.util.UUID.randomUUID().toString() }
        doc.protect(
            StandardProtectionPolicy(owner, user, doc.currentAccessPermission).apply { encryptionKeyLength = 256 },
        )
    }

    private fun load(file: File, password: String?): PDDocument = try {
        PDDocument.load(file, password.orEmpty(), MemoryUsageSetting.setupTempFileOnly())
    } catch (e: InvalidPasswordException) {
        throw PdfProtectedException("The PDF needs a password, or it's wrong", e)
    }

    /** pdfbox and PdfRenderer read files, not content URIs. */
    private fun copyIn(uri: Uri, name: String): File {
        val file = File(workDir, name)
        val source = try {
            context.contentResolver.openInputStream(uri)
        } catch (e: SecurityException) {
            throw StorageException("Not allowed to read $uri", e)
        } ?: throw FileNotFoundException(uri.toString())
        source.use { from -> file.outputStream().use { from.copyTo(it) } }
        return file
    }

    private fun output(job: PdfJob) = File(workDir, "${job.name}.pdf")
}
