package cauldron.app;

import android.app.Activity;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.hardware.input.InputManager;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import androidx.activity.ComponentActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class CauldronActivity extends ComponentActivity implements SurfaceHolder.Callback, InputManager.InputDeviceListener {
    static {
        System.loadLibrary("cauldron_app");
    }

    private static native void start(String root, String data);
    private static native void surface(Surface surface, int width, int height);
    private static native void surfaceGone();
    private static native void gpuSurface(Surface surface);
    private static native void gpuSurfaceGone();
    private static native void screen(int width, int height, float scale, float top, float right, float bottom, float left);
    private static native void touches(long[] ids, int[] phases, float[] xs, float[] ys);
    private static native void lifecycle(int state);
    private static native void back();
    private static native void padConnected(int device, String name);
    private static native void padDisconnected(int device);
    private static native void padButton(int device, String button, boolean pressed);
    private static native void padAxis(int device, String axis, float value);
    static native void uiEvent(byte[] json);
    static native void result(byte[] json);
    private static native void network(byte[] json);
    private static native void url(byte[] url);
    static native void background();
    static native void posture(int fold, boolean hasAngle, float angle, boolean hasHinge, int x, int y, int width, int height, boolean vertical, boolean separating);

    static CauldronActivity current;
    private boolean nativeUi;
    private static boolean started;

    private final OnBackInvokedCallback gameBack = CauldronActivity::back;
    private FrameLayout layout;
    private SurfaceView surfaceView;
    private SurfaceView gpuView;
    private OverlayView overlayView;
    private final HashMap<String, Float> padState = new HashMap<>();

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        current = this;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getAttributes().layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;

        layout = new FrameLayout(this);
        surfaceView = new SurfaceView(this);
        surfaceView.getHolder().addCallback(this);
        gpuView = gpuSurfaceView();
        overlayView = new OverlayView(this);
        layout.addView(surfaceView);
        layout.addView(gpuView);
        layout.addView(overlayView);
        setContentView(layout);
        if (appOfControls()) holdSplash();
        hideSystemBars();

        layout.setOnApplyWindowInsetsListener((view, insets) -> {
            reportScreen(view.getWidth(), view.getHeight(), insets);
            return insets;
        });
        layout.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) ->
            reportScreen(right - left, bottom - top, view.getRootWindowInsets()));

        getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, gameBack);

        startBeam(this);
        CauldronFold.watch(this);
        CauldronUi.show();
        opened(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        opened(intent);
    }

    private void opened(Intent intent) {
        if (Intent.ACTION_VIEW.equals(intent.getAction()) && intent.getDataString() != null) {
            url(intent.getDataString().getBytes(StandardCharsets.UTF_8));
            return;
        }
        if (!CauldronPush.INSTANCE.opened(this, intent)) CauldronNotifications.INSTANCE.opened(intent);
    }

    private boolean appOfControls() {
        try {
            Bundle meta = getPackageManager().getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA).metaData;
            return meta != null && meta.getBoolean("cauldron.native_ui");
        } catch (PackageManager.NameNotFoundException ownPackage) {
            throw new IllegalStateException(ownPackage);
        }
    }

    private void holdSplash() {
        surfaceView.setVisibility(View.GONE);
        gpuView.setVisibility(View.GONE);
        View content = findViewById(android.R.id.content);
        content.getViewTreeObserver().addOnPreDrawListener(new ViewTreeObserver.OnPreDrawListener() {
            @Override
            public boolean onPreDraw() {
                if (!nativeUi) return false;
                content.getViewTreeObserver().removeOnPreDrawListener(this);
                return true;
            }
        });
    }

    void showNativeUi(View view) {
        nativeUi = true;
        getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(gameBack);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        androidx.activity.EdgeToEdge.enable(this);
        WindowInsetsController controller = getWindow().getInsetsController();
        if (controller != null) controller.show(WindowInsets.Type.systemBars());
        surfaceView.setVisibility(View.GONE);
        gpuView.setVisibility(View.GONE);
        overlayView.setVisibility(View.GONE);
        layout.addView(view);
    }

    private SurfaceView gpuSurfaceView() {
        SurfaceView view = new SurfaceView(this);
        view.setZOrderMediaOverlay(true);
        view.setVisibility(View.GONE);
        view.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder holder) {}

            @Override
            public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                gpuSurface(holder.getSurface());
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder holder) {
                gpuSurfaceGone();
            }
        });
        return view;
    }

    private void hideSystemBars() {
        if (nativeUi) return;
        WindowInsetsController controller = getWindow().getInsetsController();
        if (controller != null) {
            controller.hide(WindowInsets.Type.systemBars());
            controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }

    private void reportScreen(int width, int height, WindowInsets insets) {
        if (width <= 0 || height <= 0) return;
        float top = 0, right = 0, bottom = 0, left = 0;
        if (insets != null) {
            android.graphics.Insets cutout = insets.getInsetsIgnoringVisibility(WindowInsets.Type.displayCutout());
            top = cutout.top;
            right = cutout.right;
            bottom = cutout.bottom;
            left = cutout.left;
        }
        screen(width, height, getResources().getDisplayMetrics().density, top, right, bottom, left);
    }

    /** Starts the app's BEAM once per process, from the activity or from background work. */
    static synchronized void startBeam(Context context) {
        if (started) return;
        started = true;
        Context app = context.getApplicationContext();
        CauldronDevice.INSTANCE.setContext(app);
        File root = new File(app.getFilesDir(), "otp");
        unpackRelease(app, root);
        writeResolver(app, new File(app.getFilesDir(), "inetrc"));
        start(root.getAbsolutePath(), app.getFilesDir().getAbsolutePath());
        watchNetwork(app);
    }

    private static void writeResolver(Context context, File file) {
        StringBuilder text = new StringBuilder("{lookup, [file, dns]}.\n");
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        LinkProperties link = connectivity == null ? null : connectivity.getLinkProperties(connectivity.getActiveNetwork());
        if (link != null) {
            for (InetAddress server : link.getDnsServers()) text.append("{nameserver, ").append(erlangAddress(server)).append("}.\n");
        }
        try (FileOutputStream stream = new FileOutputStream(file)) {
            stream.write(text.toString().getBytes(StandardCharsets.UTF_8));
        } catch (IOException error) {
            throw new IllegalStateException("could not write the resolver settings", error);
        }
    }

    private static void watchNetwork(Context context) {
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        if (connectivity == null) return;
        connectivity.registerDefaultNetworkCallback(new ConnectivityManager.NetworkCallback() {
            @Override
            public void onLinkPropertiesChanged(Network changed, LinkProperties link) {
                network(nameservers(link));
            }
        });
    }

    private static byte[] nameservers(LinkProperties link) {
        StringBuilder text = new StringBuilder("{\"nameservers\":[");
        List<InetAddress> servers = link.getDnsServers();
        for (int index = 0; index < servers.size(); index++) {
            if (index > 0) text.append(',');
            text.append('"').append(servers.get(index).getHostAddress()).append('"');
        }
        return text.append("]}").toString().getBytes(StandardCharsets.UTF_8);
    }

    private static String erlangAddress(InetAddress address) {
        byte[] bytes = address.getAddress();
        StringBuilder text = new StringBuilder("{");
        int step = bytes.length == 4 ? 1 : 2;
        for (int index = 0; index < bytes.length; index += step) {
            if (index > 0) text.append(",");
            int part = step == 1 ? bytes[index] & 0xff : ((bytes[index] & 0xff) << 8) | (bytes[index + 1] & 0xff);
            text.append(part);
        }
        return text.append("}").toString();
    }

    private static void unpackRelease(Context context, File root) {
        String stamp = releaseStamp(context);
        File marker = new File(root, ".stamp");
        if (marker.exists() && stamp.equals(readText(marker))) return;
        deleteTree(root);
        root.mkdirs();
        try (ZipInputStream zip = new ZipInputStream(context.getAssets().open("otp.zip"))) {
            byte[] buffer = new byte[65536];
            for (ZipEntry entry = zip.getNextEntry(); entry != null; entry = zip.getNextEntry()) {
                File out = new File(root, entry.getName());
                if (entry.isDirectory()) {
                    out.mkdirs();
                    continue;
                }
                out.getParentFile().mkdirs();
                try (FileOutputStream stream = new FileOutputStream(out)) {
                    for (int read = zip.read(buffer); read > 0; read = zip.read(buffer)) stream.write(buffer, 0, read);
                }
            }
            try (FileOutputStream stream = new FileOutputStream(marker)) {
                stream.write(stamp.getBytes(StandardCharsets.UTF_8));
            }
        } catch (IOException error) {
            throw new IllegalStateException("could not unpack the release", error);
        }
    }

    private static String releaseStamp(Context context) {
        try (InputStream stream = context.getAssets().open("otp.stamp")) {
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8).trim();
        } catch (IOException error) {
            throw new IllegalStateException("the app has no otp.stamp", error);
        }
    }

    private static String readText(File file) {
        try {
            return new String(java.nio.file.Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8).trim();
        } catch (IOException error) {
            return "";
        }
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteTree(child);
        file.delete();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {}

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        surface(holder.getSurface(), width, height);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        surfaceGone();
    }

    @Override
    protected void onResume() {
        super.onResume();
        hideSystemBars();
        InputManager input = getSystemService(InputManager.class);
        input.registerInputDeviceListener(this, null);
        for (int id : input.getInputDeviceIds()) onInputDeviceAdded(id);
        lifecycle(0);
    }

    @Override
    protected void onPause() {
        lifecycle(1);
        getSystemService(InputManager.class).unregisterInputDeviceListener(this);
        super.onPause();
    }

    @Override
    protected void onStop() {
        lifecycle(2);
        super.onStop();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        int count = event.getPointerCount();
        boolean single = action == MotionEvent.ACTION_POINTER_DOWN || action == MotionEvent.ACTION_POINTER_UP;
        int only = single ? event.getActionIndex() : -1;
        int phase = phaseOf(action);
        int size = single ? 1 : count;
        long[] ids = new long[size];
        int[] phases = new int[size];
        float[] xs = new float[size];
        float[] ys = new float[size];
        int at = 0;
        for (int i = 0; i < count; i++) {
            if (single && i != only) continue;
            ids[at] = event.getPointerId(i);
            phases[at] = phase;
            xs[at] = event.getX(i);
            ys[at] = event.getY(i);
            at++;
        }
        touches(ids, phases, xs, ys);
        return true;
    }

    private static int phaseOf(int action) {
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN:
                return 0;
            case MotionEvent.ACTION_MOVE:
                return 1;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
                return 2;
            default:
                return 3;
        }
    }

    private static boolean isGamepad(int sources) {
        return (sources & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
            || (sources & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
    }

    @Override
    public void onInputDeviceAdded(int id) {
        InputDevice device = InputDevice.getDevice(id);
        if (device != null && !device.isVirtual() && isGamepad(device.getSources())) padConnected(id, device.getName());
    }

    @Override
    public void onInputDeviceRemoved(int id) {
        padDisconnected(id);
    }

    @Override
    public void onInputDeviceChanged(int id) {}

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        String button = isGamepad(event.getSource()) ? buttonOf(event.getKeyCode()) : null;
        if (button == null) return super.dispatchKeyEvent(event);
        if (event.getRepeatCount() == 0) padButton(event.getDeviceId(), button, event.getAction() == KeyEvent.ACTION_DOWN);
        return true;
    }

    private static String buttonOf(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_BUTTON_A: return "a";
            case KeyEvent.KEYCODE_BUTTON_B: return "b";
            case KeyEvent.KEYCODE_BUTTON_X: return "x";
            case KeyEvent.KEYCODE_BUTTON_Y: return "y";
            case KeyEvent.KEYCODE_BUTTON_L1: return "left_bumper";
            case KeyEvent.KEYCODE_BUTTON_R1: return "right_bumper";
            case KeyEvent.KEYCODE_BUTTON_START: return "start";
            case KeyEvent.KEYCODE_BUTTON_SELECT: return "back";
            case KeyEvent.KEYCODE_BUTTON_MODE: return "guide";
            case KeyEvent.KEYCODE_BUTTON_THUMBL: return "left_stick";
            case KeyEvent.KEYCODE_BUTTON_THUMBR: return "right_stick";
            case KeyEvent.KEYCODE_DPAD_UP: return "dpad_up";
            case KeyEvent.KEYCODE_DPAD_DOWN: return "dpad_down";
            case KeyEvent.KEYCODE_DPAD_LEFT: return "dpad_left";
            case KeyEvent.KEYCODE_DPAD_RIGHT: return "dpad_right";
            default: return null;
        }
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if (!isGamepad(event.getSource()) || event.getActionMasked() != MotionEvent.ACTION_MOVE)
            return super.dispatchGenericMotionEvent(event);
        int device = event.getDeviceId();
        axis(device, "left_x", event.getAxisValue(MotionEvent.AXIS_X));
        axis(device, "left_y", event.getAxisValue(MotionEvent.AXIS_Y));
        axis(device, "right_x", event.getAxisValue(MotionEvent.AXIS_Z));
        axis(device, "right_y", event.getAxisValue(MotionEvent.AXIS_RZ));
        axis(device, "left_trigger", Math.max(event.getAxisValue(MotionEvent.AXIS_LTRIGGER), event.getAxisValue(MotionEvent.AXIS_BRAKE)));
        axis(device, "right_trigger", Math.max(event.getAxisValue(MotionEvent.AXIS_RTRIGGER), event.getAxisValue(MotionEvent.AXIS_GAS)));
        float hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X);
        float hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
        hat(device, "dpad_left", hatX < -0.5f);
        hat(device, "dpad_right", hatX > 0.5f);
        hat(device, "dpad_up", hatY < -0.5f);
        hat(device, "dpad_down", hatY > 0.5f);
        return true;
    }

    private void axis(int device, String name, float value) {
        String key = device + ":" + name;
        Float last = padState.get(key);
        if (last != null && Math.abs(last - value) < 0.01f) return;
        padState.put(key, value);
        padAxis(device, name, value);
    }

    private void hat(int device, String button, boolean pressed) {
        String key = device + ":" + button;
        float value = pressed ? 1f : 0f;
        Float last = padState.get(key);
        padState.put(key, value);
        if (last == null ? pressed : last != value) padButton(device, button, pressed);
    }

    static void quit() {
        CauldronActivity activity = current;
        if (activity == null) System.exit(0);
        activity.runOnUiThread(() -> {
            activity.finishAndRemoveTask();
            System.exit(0);
        });
    }

    static void ui(byte[] json) {
        CauldronUi.patch(json);
    }

    static void request(byte[] json) {
        CauldronDevice.request(json);
    }

    static void showGpu(boolean shown) {
        CauldronActivity activity = current;
        if (activity == null) return;
        activity.runOnUiThread(() -> activity.gpuView.setVisibility(shown ? View.VISIBLE : View.GONE));
    }

    static void overlay(byte[] packed) {
        CauldronActivity activity = current;
        if (activity == null) return;
        List<Shape> shapes = Shape.decode(packed);
        activity.runOnUiThread(() -> activity.overlayView.show(shapes));
    }

    static final class Shape {
        final float x, y, radius;
        final boolean held;
        final int alpha;
        final String label;

        Shape(float x, float y, float radius, boolean held, int alpha, String label) {
            this.x = x;
            this.y = y;
            this.radius = radius;
            this.held = held;
            this.alpha = alpha;
            this.label = label;
        }

        static List<Shape> decode(byte[] packed) {
            List<Shape> shapes = new ArrayList<>();
            ByteBuffer buffer = ByteBuffer.wrap(packed).order(ByteOrder.LITTLE_ENDIAN);
            while (buffer.remaining() >= 16) {
                float x = buffer.getFloat(), y = buffer.getFloat(), radius = buffer.getFloat();
                boolean held = buffer.get() != 0;
                int alpha = buffer.get() & 0xff;
                int length = buffer.getShort() & 0xffff;
                if (buffer.remaining() < length) break;
                byte[] label = new byte[length];
                buffer.get(label);
                shapes.add(new Shape(x, y, radius, held, alpha, new String(label, StandardCharsets.UTF_8)));
            }
            return shapes;
        }
    }

    static final class OverlayView extends View {
        private final Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float density;
        private List<Shape> shapes = new ArrayList<>();

        OverlayView(Activity activity) {
            super(activity);
            density = activity.getResources().getDisplayMetrics().density;
            ring.setStyle(Paint.Style.STROKE);
            ring.setStrokeWidth(2.5f * density);
            fill.setStyle(Paint.Style.FILL);
            text.setTextAlign(Paint.Align.CENTER);
            text.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        }

        private void drawLabel(Canvas canvas, Shape shape) {
            String[] lines = shape.label.split(" ", 2);
            text.setTextSize(shape.radius * 0.42f);
            float widest = 1;
            for (String line : lines) widest = Math.max(widest, text.measureText(line));
            text.setTextSize(Math.min(text.getTextSize(), text.getTextSize() * shape.radius * 1.6f / widest));
            float step = text.getTextSize() * 1.15f;
            float first = shape.y - step * (lines.length - 1) / 2 + text.getTextSize() * 0.35f;
            for (int index = 0; index < lines.length; index++)
                canvas.drawText(lines[index], shape.x, first + index * step, text);
        }

        void show(List<Shape> next) {
            shapes = next;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            for (Shape shape : shapes) {
                int shade = shape.held ? 255 : 0;
                fill.setColor(Color.argb((shape.held ? 102 : 82) * shape.alpha / 255, shade, shade, shade));
                ring.setColor(Color.argb(217 * shape.alpha / 255, 255, 255, 255));
                ring.setShadowLayer(2.5f * density, 0, 0, Color.argb(179 * shape.alpha / 255, 0, 0, 0));
                text.setColor(Color.argb(242 * shape.alpha / 255, 255, 255, 255));
                text.setShadowLayer(1.5f * density, 0, 0, Color.argb(230 * shape.alpha / 255, 0, 0, 0));
                canvas.drawCircle(shape.x, shape.y, shape.radius, fill);
                canvas.drawCircle(shape.x, shape.y, shape.radius, ring);
                if (!shape.label.isEmpty()) drawLabel(canvas, shape);
            }
        }
    }
}
