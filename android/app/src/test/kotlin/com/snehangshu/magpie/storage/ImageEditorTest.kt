package com.snehangshu.magpie.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImageEditorTest {
    @Test
    fun bestQualityIsTheHighestThatFits() {
        assertEquals(85, ImageEditor.bestQuality(85) { true })
        assertEquals(42, ImageEditor.bestQuality(85) { it <= 42 })
        assertEquals(ImageEditor.MIN_QUALITY, ImageEditor.bestQuality(85) { it <= ImageEditor.MIN_QUALITY })
        assertNull(ImageEditor.bestQuality(85) { false })
        assertNull(ImageEditor.bestQuality(5) { false })
    }
}
