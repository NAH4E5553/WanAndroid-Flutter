package dev.portable.album_picker_example

/**
 * Release variant: the controlled fixture channel must never exist. The
 * fixture class itself is absent from this variant's classpath (src/debug is
 * not shared into release); the switch stays off as a second guard.
 */
object FixtureGate {
    const val ENABLED = false
}
