package com.example.xpanoverlay;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;

/**
 * XPan crop-mask overlay for Sony PMCA (PlayMemories Camera Apps) devices.
 *
 * Draws top/bottom black letterbox bars matching a target aspect ratio
 * (XPan 65:24, 2.39:1 cinema, or native 3:2), plus an optional dual
 * safety frame (90% action safe, 80% title safe) inside the active area.
 *
 * The overlay is a plain top-level View of the PMCA Activity, so it is
 * rendered on the camera screen / EVF while the app is running. It is a
 * preview aid only: recorded images/videos are NOT modified.
 */
public class OverlayView extends View {

    public static final float ASPECT_XPAN = 65.0f / 24.0f; // ~2.708
    public static final float ASPECT_239  = 2.39f;
    public static final float ASPECT_32   = 3.0f / 2.0f;

    private final Paint maskPaint;
    private final Paint actionSafePaint;
    private final Paint titleSafePaint;
    private final Paint labelPaint;

    private float currentAspect = ASPECT_XPAN;
    private boolean maskVisible = true;
    private boolean safeFrameVisible = true;
    private String label = "XPan 2.7:1";

    public OverlayView(Context context) {
        super(context);

        maskPaint = new Paint();
        maskPaint.setColor(Color.BLACK);
        maskPaint.setStyle(Paint.Style.FILL);
        maskPaint.setAntiAlias(true);

        actionSafePaint = new Paint();
        actionSafePaint.setColor(Color.WHITE);
        actionSafePaint.setStyle(Paint.Style.STROKE);
        actionSafePaint.setStrokeWidth(1.5f);
        actionSafePaint.setAntiAlias(true);

        titleSafePaint = new Paint();
        titleSafePaint.setColor(Color.WHITE);
        titleSafePaint.setStyle(Paint.Style.STROKE);
        titleSafePaint.setStrokeWidth(1.0f);
        titleSafePaint.setAntiAlias(true);

        labelPaint = new Paint();
        labelPaint.setColor(Color.argb(200, 255, 255, 255));
        labelPaint.setTextSize(18);
        labelPaint.setAntiAlias(true);
        labelPaint.setShadowLayer(2.0f, 0, 0, Color.BLACK);
    }

    public void setAspect(float aspect) {
        currentAspect = aspect;
        if (Math.abs(aspect - ASPECT_XPAN) < 0.001f) {
            label = "XPan 2.7:1";
        } else if (Math.abs(aspect - ASPECT_239) < 0.001f) {
            label = "2.39:1";
        } else {
            label = "3:2";
        }
        invalidate();
    }

    public void setMaskVisible(boolean visible) {
        maskVisible = visible;
        invalidate();
    }

    public boolean isMaskVisible() {
        return maskVisible;
    }

    public void setSafeFrameVisible(boolean visible) {
        safeFrameVisible = visible;
        invalidate();
    }

    public boolean isSafeFrameVisible() {
        return safeFrameVisible;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        int w = getWidth();
        int h = getHeight();
        if (w <= 0 || h <= 0) {
            return;
        }

        // Active (un-masked) picture area. Clamped to the view height so that
        // the 3:2 mode simply fills the screen instead of producing a
        // negative top margin.
        float cropHeight = Math.min(w / currentAspect, (float) h);
        float top = (h - cropHeight) / 2.0f;
        float bottom = top + cropHeight;

        if (maskVisible) {
            canvas.drawRect(0, 0, w, top, maskPaint);
            canvas.drawRect(0, bottom, w, h, maskPaint);
        }

        if (safeFrameVisible) {
            // 90% action safe frame
            float actW = w * 0.90f;
            float actH = cropHeight * 0.90f;
            canvas.drawRect((w - actW) / 2.0f, top + (cropHeight - actH) / 2.0f,
                    (w + actW) / 2.0f, top + (cropHeight + actH) / 2.0f, actionSafePaint);

            // 80% title safe frame
            float titW = w * 0.80f;
            float titH = cropHeight * 0.80f;
            canvas.drawRect((w - titW) / 2.0f, top + (cropHeight - titH) / 2.0f,
                    (w + titW) / 2.0f, top + (cropHeight + titH) / 2.0f, titleSafePaint);
        }

        // Small mode label, top-right corner
        float textW = labelPaint.measureText(label);
        canvas.drawText(label, w - textW - 8.0f, 22.0f, labelPaint);
    }
}
