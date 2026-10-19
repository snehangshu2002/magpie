package com.snehangshu.magpie.engine

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * The last event of each finished download (`saved`, `failed`, `cancelled`),
 * kept on disk until Dart takes it. Progress events are lost while the UI is
 * gone (e.g. the user left the app), so Dart reads these to update its history.
 */
internal object DownloadResults {
    private const val PREFS = "download_results"

    @Synchronized
    fun put(context: Context, event: Map<String, Any?>) {
        val id = event["id"] as? String ?: return
        prefs(context).edit()
            .putString(id, JSONObject(event.filterValues { it != null }).toString())
            .apply()
    }

    /** Returns the stored events and forgets them. */
    @Synchronized
    fun take(context: Context): List<Map<String, Any?>> {
        val prefs = prefs(context)
        val events = prefs.all.values.mapNotNull { value ->
            runCatching {
                val json = JSONObject(value as String)
                json.keys().asSequence().associateWith { key ->
                    when (val value = json.get(key)) {
                        // filePaths: the channel can't send a JSONArray.
                        is JSONArray -> List(value.length()) { value.get(it) }
                        else -> value
                    }
                }
            }.getOrNull()
        }
        prefs.edit().clear().commit()
        return events
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
