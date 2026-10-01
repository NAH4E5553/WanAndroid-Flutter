package dev.portable.album_picker_example

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        // Variant switch: debug and profile builds load the controlled fixture
        // gateway; release keeps both the switch off and the class absent.
        if (FixtureGate.ENABLED) {
            try {
                Class.forName("dev.portable.album_picker_example.ControlledAlbumFixtures")
                    .getConstructor(Context::class.java, FlutterEngine::class.java)
                    .newInstance(this, engine)
            } catch (_: ClassNotFoundException) { }
        }
    }
}
