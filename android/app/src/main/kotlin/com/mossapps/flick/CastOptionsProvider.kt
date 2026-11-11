package com.mossapps.flick

import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.SessionProvider
import android.content.Context

// Lokal receiver, shared with desktop: artwork, lyrics and synchronized video.
// Referenced by AndroidManifest OPTIONS_PROVIDER_CLASS_NAME metadata.
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        return CastOptions.Builder()
            .setReceiverApplicationId("2060B9B3")
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): MutableList<SessionProvider>? {
        return null
    }
}
