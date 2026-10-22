package com.snehangshu.magpie.engine

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class SavedFilesTest {
    private lateinit var dir: File

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("saved-files").toFile()
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun file(name: String, size: Int = 1, bytes: ByteArray? = null) =
        File(dir, name).apply { writeBytes(bytes ?: ByteArray(size)) }

    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()) + ByteArray(20)

    @Test
    fun `playlist videos come in order, one each, without their index`() {
        file("10 Gamma.mp4")
        file("2 Beta.mp4")
        file("1 Alpha.mp4", size = 20)
        // A stream left next to its merged file, and one yt-dlp didn't finish.
        file("1 Alpha.f140.m4a", size = 5)
        file("3 Delta.mp4.part")

        assertEquals(
            listOf("Alpha.mp4", "Beta.mp4", "Gamma.mp4"),
            playlistFiles(dir).map { it.name },
        )
    }

    @Test
    fun `playlist videos with the same title keep their index`() {
        file("1 Same.mp4")
        file("2 Same.mp4")

        assertEquals(listOf("Same.mp4", "2 Same.mp4"), playlistFiles(dir).map { it.name })
    }

    @Test
    fun `post items are named by the title, videos without their thumbnails`() {
        file("1 AAA.mp4", size = 5)
        file("1 AAA.jpg", size = 50, bytes = jpeg) // the video's thumbnail
        file("2 BBB.jpg", bytes = jpeg)
        // Instagram serves JPEGs under a .heic name.
        file("3 CCC.heic", bytes = jpeg)

        val saved = postFiles(dir, "Trip", picked = null) { it.extension == "mp4" }

        assertEquals(listOf("Trip 1.mp4", "Trip 2.jpg", "Trip 3.jpg"), saved.map { it.name })
    }

    @Test
    fun `picked post items keep their place in the post`() {
        file("2 BBB.jpg", bytes = jpeg)
        file("5 EEE.jpg", bytes = jpeg)

        val saved = postFiles(dir, "Trip", picked = listOf(5, 2)) { false }

        assertEquals(listOf("Trip 2.jpg", "Trip 5.jpg"), saved.map { it.name })
    }

    @Test
    fun `a single item has no number`() {
        file("0 AAA.jpg", bytes = jpeg)

        assertEquals(listOf("Trip.jpg"), postFiles(dir, "Trip", null) { false }.map { it.name })
    }
}
