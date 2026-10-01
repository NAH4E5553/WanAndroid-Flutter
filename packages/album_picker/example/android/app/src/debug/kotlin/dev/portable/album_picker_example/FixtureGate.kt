package dev.portable.album_picker_example

/**
 * Per-variant fixture switch. Debug and Profile builds allow the controlled
 * fixture channel; the Release variant carries its own copy with the switch
 * hard-disabled and no fixture class on the classpath.
 */
object FixtureGate {
    const val ENABLED = true
}
