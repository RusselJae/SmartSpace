package com.example.smartspace_ar

/**
 * Holds bulky AR editor launch data that must not ride in an Intent (Binder limit).
 *
 * [MainActivity.openArEditor] writes here; [ArEditorActivity] reads once in onCreate.
 */
object ArEditorLaunchCache {
    @Volatile
    var variantProductsJson: String? = null

    fun takeVariantProductsJson(): String? {
        val json = variantProductsJson
        variantProductsJson = null
        return json
    }
}
