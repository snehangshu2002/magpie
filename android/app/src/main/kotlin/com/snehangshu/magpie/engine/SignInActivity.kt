package com.snehangshu.magpie.engine

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.snehangshu.magpie.R

/**
 * A plain browser page where the user signs in to a site, so yt-dlp can
 * read what their account can see. "Done" keeps the site's cookies
 * ([Cookies]); back leaves without saving.
 */
class SignInActivity : Activity() {
    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL) ?: return finish()

        web = WebView(this).apply {
            // Sign-in pages don't work without JavaScript.
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            webViewClient = WebViewClient()
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(16), dp(8), dp(8), dp(8))
            addView(
                TextView(this@SignInActivity).apply {
                    text = getString(R.string.sign_in_hint, Cookies.siteOf(url))
                },
                LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f),
            )
            addView(
                Button(this@SignInActivity).apply {
                    text = getString(R.string.sign_in_done)
                    setOnClickListener {
                        val saved = Cookies.saveFromWebView(this@SignInActivity, url)
                        setResult(RESULT_OK, Intent().putExtra(EXTRA_COUNT, saved))
                        finish()
                    }
                },
            )
        }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                fitsSystemWindows = true
                addView(bar, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(web, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
            },
        )
        if (savedInstanceState == null) web.loadUrl(url) else web.restoreState(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }

    @Deprecated("Activity.onBackPressed; no AndroidX here")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        if (::web.isInitialized) web.destroy()
        super.onDestroy()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_COUNT = "count"
    }
}
