package dev.portable.album_picker
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import kotlin.test.*

class BoundedOutputStreamTest {
    @Test fun limitsBeforeWritingAndKeepsTheOriginalFailure() {
        val disk = ByteArrayOutputStream()
        val bounded = BoundedOutputStream(disk, 3)
        bounded.write(byteArrayOf(1, 2))
        assertFailsWith<ExportFailure> { bounded.write(byteArrayOf(3, 4)) }
        assertEquals(2, disk.size())
        assertEquals("budgetExceeded", (bounded.failure as ExportFailure).code)
    }
    @Test fun cancellationDoesNotWriteEvenIfCallerIgnoresException() {
        val disk = ByteArrayOutputStream()
        val bounded = BoundedOutputStream(disk, 100) { throw ExportFailure("cancelled") }
        assertFailsWith<ExportFailure> { bounded.write(1) }
        assertEquals(0, disk.size())
    }
    @Test fun diskFailureIsRetainedForCodecCallers() {
        val disk = object : OutputStream() { override fun write(value: Int) { throw IOException("controlled disk failure") } }
        val bounded = BoundedOutputStream(disk, 100)
        assertFailsWith<IOException> { bounded.write(1) }
        assertNotNull(bounded.failure)
        assertEquals(0L, bounded.count)
    }
}
