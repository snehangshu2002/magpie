package com.snehangshu.magpie

import android.content.Intent
import android.content.IntentSender

/** What bridges need from the activity; implemented by [MainActivity]. */
interface ActivityHost {
    /** Requests those of [permissions] not yet granted; returns once the user answers. */
    suspend fun requestPermissions(permissions: List<String>)

    /** Shows a system confirmation (e.g. MediaStore's delete prompt); true if accepted. */
    suspend fun confirm(request: IntentSender): Boolean

    /** Starts [intent] from the activity; throws ActivityNotFoundException if nothing handles it. */
    fun launch(intent: Intent)
}
