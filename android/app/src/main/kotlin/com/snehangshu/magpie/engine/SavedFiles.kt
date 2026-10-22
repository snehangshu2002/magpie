package com.snehangshu.magpie.engine

import com.snehangshu.magpie.storage.MediaStoreSaver
import java.io.File

/** Extensions of files yt-dlp leaves while it is still working on them. */
private val TEMP_EXTENSIONS = setOf("part", "ytdl", "temp")

/** The files in [dir] yt-dlp finished, leaving out its partial ones. */
internal fun finishedFiles(dir: File): List<File> =
    dir.listFiles()?.filter { it.isFile && it.extension !in TEMP_EXTENSIONS }.orEmpty()

/**
 * The videos of a playlist yt-dlp saved in [dir] as `<index> <name>.<ext>`,
 * in playlist order, renamed without the index. One per item: the biggest
 * when a stream was left unmerged next to the merged file. An item whose
 * name another item already took keeps its index.
 */
internal fun playlistFiles(dir: File): List<File> =
    finishedFiles(dir)
        .groupBy { it.name.substringBefore(' ').toIntOrNull() ?: 0 }
        .toSortedMap()
        .map { (_, group) -> group.maxBy { it.length() } }
        .map { file ->
            val target = File(dir, file.name.substringAfter(' '))
            if (target.exists() || !file.renameTo(target)) file else target
        }

/**
 * The items of a post yt-dlp saved in [dir] as `<index> <id>.<ext>`, in
 * post order, renamed `<title> <n>.<ext>` ([title] null keeps the id). A
 * video item's file is the video ([isVideo]), not the thumbnail written
 * next to it. [picked] are the 1-based items asked for; null for all.
 */
internal fun postFiles(
    dir: File,
    title: String?,
    picked: List<Int>?,
    isVideo: (File) -> Boolean,
): List<File> {
    val saved = finishedFiles(dir)
        .groupBy { it.name.substringBefore('.') }
        .toSortedMap(compareBy { it.substringBefore(' ').toIntOrNull() ?: 0 })
        .map { (_, group) -> group.firstOrNull(isVideo) ?: group.maxBy { it.length() } }
    val asked = picked?.sorted()
    return saved.mapIndexed { i, file ->
        // Instagram's photos are JPEGs whose URL ends in ".heic".
        val ext = MediaStoreSaver.imageExtensionOf(file) ?: file.extension
        val base = title ?: file.name.substringBefore('.').substringAfter(' ')
        // Picked items keep their place in the post, so items saved in
        // separate runs don't all share the post's name. If one produced
        // nothing, yt-dlp's playlist_index prefix still gives the place.
        val number = when {
            asked == null -> (i + 1).takeIf { saved.size > 1 }
            saved.size == asked.size -> asked[i]
            else -> file.name.substringBefore(' ').toIntOrNull()
        }
        val name = if (number != null) "$base $number.$ext" else "$base.$ext"
        File(dir, name).also { file.renameTo(it) }
    }
}
