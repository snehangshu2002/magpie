package com.snehangshu.magpie.engine

import android.content.Context
import java.io.File
import java.io.IOException

/** How to re-encode a video so it fits [targetBytes]; chosen by Dart (`fitVideo`). */
data class FitSpec(
    val targetBytes: Long,
    val durationMs: Long,
    val videoKbps: Int,
    /** 0 drops the audio. */
    val audioKbps: Int,
    /** The output's shorter side, in pixels; never upscaled. */
    val maxShortSide: Int,
    /** File name without extension. */
    val name: String,
)

/** The encode came out bigger than the target even at the lowest bitrate tried. */
class FitTooLargeException(message: String) : IOException(message)

/** FFmpeg failed to encode the video. */
class EncodeException(message: String) : IOException(message)

/**
 * Re-encodes a video with the FFmpeg that youtubedl-android bundles, into an
 * H.264/AAC MP4 no bigger than [FitSpec.targetBytes]. Engine must be
 * initialized first (it unpacks FFmpeg's libraries).
 */
internal class VideoFitter(private val context: Context) {

    /**
     * Encodes [input] into [output]. A single-pass encode can overshoot the
     * bitrate a little, so a result over the target is encoded again at a
     * proportionally lower bitrate, up to [MAX_ATTEMPTS] times in all.
     * [onStart] receives each FFmpeg process, so a cancel can kill it.
     */
    fun fit(
        input: File,
        output: File,
        spec: FitSpec,
        onStart: (Process) -> Unit,
        onProgress: (percent: Float) -> Unit,
    ) {
        var videoKbps = spec.videoKbps
        repeat(MAX_ATTEMPTS) { attempt ->
            output.delete()
            encode(input, output, spec, videoKbps, onStart, onProgress)
            val size = output.length()
            if (size in 1..spec.targetBytes) return
            if (attempt == MAX_ATTEMPTS - 1 || videoKbps <= MIN_VIDEO_KBPS) {
                throw FitTooLargeException("$size bytes is over ${spec.targetBytes}")
            }
            // Audio is constant-bitrate; take the whole overshoot out of the video.
            val audioBytes = spec.audioKbps * 1000L / 8 * spec.durationMs / 1000
            val videoTarget = (spec.targetBytes * SAFETY - audioBytes).coerceAtLeast(1.0)
            val videoActual = (size - audioBytes).coerceAtLeast(1L)
            videoKbps = (videoKbps * videoTarget / videoActual).toInt()
                .coerceIn(MIN_VIDEO_KBPS, videoKbps - 1)
        }
    }

    private fun encode(
        input: File,
        output: File,
        spec: FitSpec,
        videoKbps: Int,
        onStart: (Process) -> Unit,
        onProgress: (Float) -> Unit,
    ) {
        val side = spec.maxShortSide
        val args = buildList {
            add(ffmpegBinary().absolutePath)
            addAll(listOf("-hide_banner", "-nostdin", "-y", "-loglevel", "error"))
            addAll(listOf("-progress", "pipe:1", "-nostats"))
            addAll(listOf("-i", input.absolutePath))
            addAll(listOf("-map", "0:v:0"))
            // Scales the shorter side down to `side`, keeping the aspect ratio
            // (-2: the other side rounded to an even number). Never upscales.
            add("-vf")
            add(
                "scale=w='if(gt(iw,ih),-2,min($side,iw))':h='if(gt(iw,ih),min($side,ih),-2)'," +
                    "format=yuv420p",
            )
            // 60 fps is wasted at sharing bitrates.
            addAll(listOf("-fpsmax", "30"))
            addAll(listOf("-c:v", "libx264", "-preset", "veryfast"))
            addAll(listOf("-b:v", "${videoKbps}k"))
            addAll(listOf("-maxrate", "${videoKbps * 3 / 2}k", "-bufsize", "${videoKbps * 2}k"))
            if (spec.audioKbps > 0) {
                addAll(listOf("-map", "0:a:0?", "-c:a", "aac", "-b:a", "${spec.audioKbps}k", "-ac", "2"))
            } else {
                add("-an")
            }
            addAll(listOf("-movflags", "+faststart"))
            add(output.absolutePath)
        }
        val process = ProcessBuilder(args)
            .redirectErrorStream(true)
            .apply { environment()["LD_LIBRARY_PATH"] = libraryPath() }
            .start()
        onStart(process)

        // With -loglevel error, anything that isn't a progress key is an error line.
        val errors = ArrayDeque<String>()
        val totalUs = spec.durationMs * 1000
        process.inputStream.bufferedReader().useLines { lines ->
            lines.forEach { line ->
                when {
                    line.startsWith("out_time_us=") -> {
                        val us = line.substringAfter('=').toLongOrNull() ?: return@forEach
                        if (totalUs > 0 && us >= 0) {
                            onProgress((us.toFloat() / totalUs * 100f).coerceIn(0f, 100f))
                        }
                    }
                    PROGRESS_KEY.matches(line) -> Unit
                    else -> {
                        errors.addLast(line)
                        if (errors.size > MAX_ERROR_LINES) errors.removeFirst()
                    }
                }
            }
        }
        val exit = process.waitFor()
        // A cancel kills the process too; the caller knows it asked and reports that instead.
        if (exit != 0) {
            throw EncodeException("ffmpeg exited with $exit: ${errors.joinToString("\n")}")
        }
    }

    private fun ffmpegBinary() = File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")

    /** Where FFmpeg.init unpacked the libraries, as youtubedl-android sets it for yt-dlp. */
    private fun libraryPath(): String {
        val packages = File(context.noBackupFilesDir, "youtubedl-android/packages")
        return listOf("python", "ffmpeg").joinToString(":") {
            File(packages, "$it/usr/lib").absolutePath
        }
    }

    private companion object {
        const val MAX_ATTEMPTS = 3
        const val MIN_VIDEO_KBPS = 80

        /** Aim a little under the target on a retry. */
        const val SAFETY = 0.95

        const val MAX_ERROR_LINES = 20

        // FFmpeg's -progress output: "frame=120", "speed=1.5x", "progress=end".
        val PROGRESS_KEY = Regex("""^[a-z_0-9]+=.*$""")
    }
}
