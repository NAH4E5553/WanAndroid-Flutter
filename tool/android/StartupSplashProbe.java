import android.content.Context;
import android.content.res.AssetManager;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import android.util.TypedValue;

/** Read-only API31+ resource regression; loads an APK without launching its app.
 * Run via app_process with APK path and resource package as arguments.
 * Actual native raster bounds must match the 96dp unmasked launcher geometry.
 * Continuous device video separately verifies window position and handoff.
 */
public final class StartupSplashProbe {
    public static void main(String[] args) {
        try { verify(args); }
        catch (Throwable error) { error.printStackTrace(); System.exit(1); }
    }
    private static void verify(String[] args) throws Exception {
        Looper.prepareMainLooper();
        Class<?> activityThread = Class.forName("android.app.ActivityThread");
        Object thread = activityThread.getMethod("systemMain").invoke(null);
        Context system = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
        AssetManager assets = AssetManager.class.getDeclaredConstructor().newInstance();
        AssetManager.class.getMethod("addAssetPath", String.class).invoke(assets, args[0]);
        for (int night : new int[]{Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES}) {
            Configuration config = new Configuration(system.getResources().getConfiguration());
            config.uiMode = (config.uiMode & ~Configuration.UI_MODE_NIGHT_MASK) | night;
            Resources resources = new Resources(assets, system.getResources().getDisplayMetrics(), config);
            Resources.Theme theme = resources.newTheme();
            theme.applyStyle(resources.getIdentifier("LaunchTheme", "style", args[1]), true);
            TypedValue icon = new TypedValue();
            require(theme.resolveAttribute(android.R.attr.windowSplashScreenAnimatedIcon, icon, true), "Missing icon");
            Drawable drawable = resources.getDrawable(icon.resourceId, theme);
            float density = resources.getDisplayMetrics().density;
            require(Math.abs(drawable.getIntrinsicWidth() / density - 288) < 1, "Canvas must be 288dp, not icon size");
            require(Math.abs(drawable.getIntrinsicHeight() / density - 288) < 1, "Canvas height must be 288dp");
            Bitmap actual = Bitmap.createBitmap(288, 288, Bitmap.Config.ARGB_8888);
            drawable.setBounds(0, 0, 288, 288);
            drawable.draw(new Canvas(actual));
            Bitmap reference = Bitmap.createBitmap(288, 288, Bitmap.Config.ARGB_8888);
            Drawable launcher = resources.getDrawable(resources.getIdentifier("ic_launcher", "mipmap", args[1]), theme);
            launcher.setBounds(96, 96, 192, 192);
            launcher.draw(new Canvas(reference));
            int minX = 288, minY = 288, maxX = -1, maxY = -1, differences = 0;
            for (int y = 0; y < 288; y++) {
                for (int x = 0; x < 288; x++) {
                    int pixel = actual.getPixel(x, y);
                    if (Color.alpha(pixel) > 128) {
                        minX = Math.min(x, minX); maxX = Math.max(x, maxX);
                        minY = Math.min(y, minY); maxY = Math.max(y, maxY);
                    }
                    if (pixel != reference.getPixel(x, y)) differences++;
                }
            }
            require(minX == 96 && minY == 96 && maxX == 191 && maxY == 191, "Visible square must be centered 96x96");
            // PNG and vector edge rasterization differ, but interiors must agree.
            require(differences < 96 * 96 * 0.08, "Frozen launcher geometry differs");
            TypedValue background = new TypedValue();
            require(theme.resolveAttribute(android.R.attr.windowSplashScreenBackground, background, true), "Missing background");
            require(background.data == (night == Configuration.UI_MODE_NIGHT_YES ? Color.BLACK : Color.WHITE), "Wrong native background");
            System.out.println("SPLASH_RESOURCE_PASS night=" + night + " bounds=96,96,191,191 differingPixels=" + differences);
            actual.recycle(); reference.recycle();
        }
        System.exit(0);
    }
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
