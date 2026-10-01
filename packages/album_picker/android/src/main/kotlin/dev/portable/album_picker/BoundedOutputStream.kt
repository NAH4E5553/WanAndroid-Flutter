package dev.portable.album_picker

import java.io.IOException
import java.io.OutputStream

internal class ExportFailure(val code: String) : IOException()

/** Counts BEFORE delegating; a codec swallowing IOExceptions cannot hide failure. */
internal class BoundedOutputStream(
    private val output: OutputStream,
    private val limit: Long,
    private val check: () -> Unit = {}
) : OutputStream() {
    var count = 0L
        private set
    var failure: IOException? = null
        private set
    private fun reserve(size: Int) {
        try {
            check()
            if (size.toLong() > limit - count) throw ExportFailure("budgetExceeded")
        } catch (e: IOException) { failure = e; throw e }
    }
    override fun write(value: Int) {
        reserve(1)
        try { output.write(value); count++ } catch (e: IOException) { failure = e; throw e }
    }
    override fun write(bytes: ByteArray, offset: Int, length: Int) {
        reserve(length)
        try { output.write(bytes, offset, length); count += length } catch (e: IOException) { failure = e; throw e }
    }
}
