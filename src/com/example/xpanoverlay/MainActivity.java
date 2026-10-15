package com.example.xpanoverlay;

import android.app.Activity;
import android.hardware.Camera;
import android.os.Bundle;
import android.os.Environment;
import android.view.KeyEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * XPan crop-mask overlay for Sony PMCA (PlayMemories Camera Apps).
 *
 * v1.2 — architecture ported from the community Recipe Lab app
 * (github.com/voxivoid/recipe-lab-sony-pmca), which shows the only working
 * way to get a live image inside a PMCA app:
 *
 *   1. Open the camera through the Sony scalar API:
 *        CameraEx.open(0, null)  ->  getNormalCamera()  ->  android.hardware.Camera
 *      (reflection, so this compiles against plain android.jar)
 *   2. Render the preview ourselves into the app's SurfaceView:
 *        camera.setPreviewDisplay(holder); camera.startPreview();
 *   3. Overlay the XPan bars with a normal View on top of the SurfaceView.
 *
 * The camera system's own LiveView does NOT render under a PMCA app window,
 * so a transparent window cannot help; the app must render the preview.
 *
 * v1.3 — shutter flow fixed: takePicture() now carries a JPEG callback that
 * writes the capture to DCIM/XPanOverlay on the card and restarts the
 * preview (the stock Camera API halts preview after a shot and never
 * resumes it on its own). A capture-in-progress guard prevents re-entrant
 * takePicture() calls from throwing.
 *
 * Keys are matched by Sony SCAN CODE (com.sony.scalar.sysutil.ScalarInput),
 * not by Android KeyEvent keycode:
 *   232 ENTER  : cycle aspect ratio (XPan -> 2.39:1 -> 3:2)
 *   103 UP     : toggle letterbox mask
 *   108 DOWN   : toggle safety frames
 *   516 S1     : auto focus (half press)
 *   518 S2     : take picture (full press)
 *   514/229    : MENU / soft key 1 : quit to camera UI
 */
public class MainActivity extends Activity implements SurfaceHolder.Callback {

    // Sony scan codes (com.sony.scalar.sysutil.ScalarInput)
    private static final int K_UP = 103, K_DOWN = 108, K_ENTER = 232,
            K_MENU = 514, K_SK1 = 229, K_S1 = 516, K_S2 = 518;

    private SurfaceHolder holder;
    private Object cameraEx;
    private Camera camera;
    private OverlayView overlay;
    private int modeIndex = 0;
    private boolean maskVisible = true;
    private boolean safeFrameVisible = true;
    private boolean capturing = false; // takePicture in flight; blocks re-entrant S2

    private static final float[] MODES = {
            OverlayView.ASPECT_XPAN,
            OverlayView.ASPECT_239,
            OverlayView.ASPECT_32
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);

        // bottom layer: the live preview, rendered by this app
        SurfaceView preview = new SurfaceView(this);
        root.addView(preview, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        holder = preview.getHolder();
        holder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS);

        // top layer: XPan bars / safety frames (a plain View is transparent by default)
        overlay = new OverlayView(this);
        root.addView(overlay, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        openCamera();
        if (camera != null) {
            holder.addCallback(this);
            // If the Surface survived the pause (no surfaceDestroyed), the
            // callback above will NOT re-fire surfaceCreated, so kick the
            // preview here when the surface is already valid.
            startPreviewIfReady();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        holder.removeCallback(this);
        try { if (camera != null) camera.stopPreview(); } catch (Throwable t) {}
        try { if (cameraEx != null) cameraEx.getClass().getMethod("release").invoke(cameraEx); } catch (Throwable t) {}
        cameraEx = null;
        camera = null;
    }

    /** open the camera via the Sony scalar API, then use it as a plain android.hardware.Camera */
    private void openCamera() {
        try {
            Class<?> cx = Class.forName("com.sony.scalar.hardware.CameraEx");
            Method open = cx.getMethod("open", int.class,
                    Class.forName("com.sony.scalar.hardware.CameraEx$OpenOptions"));
            cameraEx = open.invoke(null, 0, null);
            camera = (Camera) cx.getMethod("getNormalCamera").invoke(cameraEx);
        } catch (Throwable t) {
            cameraEx = null;
            camera = null;
        }
    }

    /** JPEG callback: persist the shot to the card, then resume the preview.
     *  takePicture() halts the preview and the PMCA firmware does not save
     *  the JPEG by itself, so both steps are mandatory here. */
    private final Camera.PictureCallback jpegCallback = new Camera.PictureCallback() {
        @Override
        public void onPictureTaken(byte[] data, Camera cam) {
            try {
                if (data != null && data.length > 0) {
                    saveJpeg(data);
                }
            } catch (Throwable t) {
                // saving must never kill the preview loop
            } finally {
                capturing = false;
                try { cam.startPreview(); } catch (Throwable t) {}
            }
        }
    };

    /** Write the JPEG bytes to DCIM/XPanOverlay/IMG_yyyyMMdd_HHmmss.jpg. */
    private void saveJpeg(byte[] data) throws Exception {
        File dir = new File(Environment.getExternalStorageDirectory(), "DCIM/XPanOverlay");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            return;
        }
        String stamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
        File out = new File(dir, "IMG_" + stamp + ".jpg");
        for (int i = 2; out.exists() && i < 100; i++) {
            out = new File(dir, "IMG_" + stamp + "_" + i + ".jpg");
        }
        FileOutputStream fos = new FileOutputStream(out);
        try {
            fos.write(data);
            fos.flush();
        } finally {
            try { fos.close(); } catch (Throwable t) {}
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder h) {
        startPreviewIfReady();
    }

    /** (re)attach the preview to the SurfaceView; safe to call repeatedly. */
    private void startPreviewIfReady() {
        try {
            if (camera != null && holder.getSurface() != null && holder.getSurface().isValid()) {
                camera.setPreviewDisplay(holder);
                camera.startPreview();
            }
        } catch (Throwable t) {
            // preview start is best-effort; a later surface event will retry
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) {}

    @Override
    public void surfaceDestroyed(SurfaceHolder h) {}

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        if (e.getAction() == KeyEvent.ACTION_DOWN) {
            return onKeyDown(e.getKeyCode(), e);
        }
        return super.dispatchKeyEvent(e);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        int sc = event.getScanCode();
        if (event.getRepeatCount() > 0) {
            return true;
        }
        switch (sc) {
            case K_ENTER:
                modeIndex = (modeIndex + 1) % MODES.length;
                overlay.setAspect(MODES[modeIndex]);
                return true;
            case K_UP:
                maskVisible = !maskVisible;
                overlay.setMaskVisible(maskVisible);
                return true;
            case K_DOWN:
                safeFrameVisible = !safeFrameVisible;
                overlay.setSafeFrameVisible(safeFrameVisible);
                return true;
            case K_S1:
                try { if (camera != null) camera.autoFocus(null); } catch (Throwable t) {}
                return true;
            case K_S2:
                if (camera != null && !capturing) {
                    capturing = true;
                    try {
                        camera.takePicture(null, null, jpegCallback);
                    } catch (Throwable t) {
                        capturing = false;
                    }
                }
                return true;
            case K_MENU:
            case K_SK1:
                finish();
                return true;
            default:
                if (keyCode == KeyEvent.KEYCODE_BACK) {
                    finish();
                    return true;
                }
                return super.onKeyDown(keyCode, event);
        }
    }
}
