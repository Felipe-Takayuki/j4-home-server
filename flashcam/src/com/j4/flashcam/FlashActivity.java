package com.j4.flashcam;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Size;
import android.view.Gravity;
import android.view.Surface;
import android.view.WindowManager;
import android.widget.TextView;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;
import java.util.Arrays;

/**
 * Takes ONE photo with the rear camera and the LED lit, then POSTs the JPEG to the bot
 * listening on 127.0.0.1:<port>/<key> and closes. Started by the Telegram bot with
 *   am start -n com.j4.flashcam/.FlashActivity --ei port N --es key SECRET
 *
 * Why an app: termux-camera-photo has no flash and Android switches the torch off as soon as
 * another client opens the camera. Here the same camera session that captures also holds the
 * torch (FLASH_MODE_TORCH), so the LED stays lit while the sensor exposes.
 */
public class FlashActivity extends Activity {
    private static final long TORCH_SETTLE_MS = 1500;   // let AE/AF adapt to the lit scene
    private static final long GIVE_UP_MS = 20000;

    private int port;
    private String key;
    private HandlerThread thread;
    private Handler h;
    private CameraDevice camera;
    private CameraCaptureSession session;
    private ImageReader reader;
    private SurfaceTexture previewTexture;   // field on purpose: if it is garbage-collected the preview surface is abandoned and the session dies
    private int sensorOrientation;
    private long firstFrameAt = 0;
    private boolean captured = false, finished = false;

    @SuppressWarnings("deprecation")
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        TextView t = new TextView(this);
        t.setText("Tirando foto…");
        t.setTextColor(Color.GRAY);
        t.setGravity(Gravity.CENTER);
        t.setBackgroundColor(Color.BLACK);
        setContentView(t);

        port = getIntent().getIntExtra("port", 0);
        key = getIntent().getStringExtra("key");
        thread = new HandlerThread("cam");
        thread.start();
        h = new Handler(thread.getLooper());
        if (port <= 0 || key == null) { finish(); return; }

        h.postDelayed(() -> fail("tempo esgotado (a câmera não respondeu)"), GIVE_UP_MS);
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            fail("sem permissão da câmera (rode flashcam/install.sh no PC)");
            return;
        }
        h.post(this::openCamera);
    }

    private void openCamera() {
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            String id = null;
            for (String c : cm.getCameraIdList()) {
                CameraCharacteristics ch = cm.getCameraCharacteristics(c);
                Integer facing = ch.get(CameraCharacteristics.LENS_FACING);
                Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK
                        && flash != null && flash) { id = c; break; }
            }
            if (id == null) { fail("não achei câmera traseira com flash"); return; }
            CameraCharacteristics ch = cm.getCameraCharacteristics(id);
            Integer so = ch.get(CameraCharacteristics.SENSOR_ORIENTATION);
            sensorOrientation = so == null ? 90 : so;
            StreamConfigurationMap map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size jpeg = pick(map.getOutputSizes(ImageFormat.JPEG), 5_000_000);
            Size prev = pick(map.getOutputSizes(SurfaceTexture.class), 640 * 480);
            reader = ImageReader.newInstance(jpeg.getWidth(), jpeg.getHeight(), ImageFormat.JPEG, 1);
            reader.setOnImageAvailableListener(r -> {
                Image img = r.acquireLatestImage();
                if (img == null) return;
                ByteBuffer buf = img.getPlanes()[0].getBuffer();
                byte[] data = new byte[buf.remaining()];
                buf.get(data);
                img.close();
                post("ok", data);
            }, h);
            previewTexture = new SurfaceTexture(10);
            previewTexture.setDefaultBufferSize(prev.getWidth(), prev.getHeight());
            final Surface ps = new Surface(previewTexture);
            cm.openCamera(id, new CameraDevice.StateCallback() {
                @Override public void onOpened(CameraDevice c) { camera = c; startSession(ps); }
                @Override public void onDisconnected(CameraDevice c) { fail("câmera desconectada ou em uso"); }
                @Override public void onError(CameraDevice c, int e) { fail("erro da câmera " + e); }
            }, h);
        } catch (CameraAccessException | SecurityException e) {
            fail("câmera: " + e.getMessage());
        }
    }

    /** Largest size not above maxArea pixels, else the smallest available. */
    private static Size pick(Size[] sizes, int maxArea) {
        Size best = null, smallest = null;
        for (Size s : sizes) {
            int a = s.getWidth() * s.getHeight();
            if (smallest == null || a < smallest.getWidth() * smallest.getHeight()) smallest = s;
            if (a <= maxArea && (best == null || a > best.getWidth() * best.getHeight())) best = s;
        }
        return best != null ? best : smallest;
    }

    private void startSession(final Surface preview) {
        try {
            camera.createCaptureSession(Arrays.asList(preview, reader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    @Override public void onConfigured(CameraCaptureSession s) {
                        session = s;
                        try {
                            CaptureRequest.Builder p = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                            p.addTarget(preview);
                            lit(p);
                            s.setRepeatingRequest(p.build(), new CameraCaptureSession.CaptureCallback() {
                                @Override public void onCaptureCompleted(CameraCaptureSession x, CaptureRequest r, TotalCaptureResult res) {
                                    long now = System.currentTimeMillis();
                                    if (firstFrameAt == 0) firstFrameAt = now;
                                    Integer ae = res.get(CaptureResult.CONTROL_AE_STATE);
                                    boolean ready = ae != null && ae == CaptureResult.CONTROL_AE_STATE_CONVERGED;
                                    if (!captured && now - firstFrameAt >= TORCH_SETTLE_MS
                                            && (ready || now - firstFrameAt >= 3500)) {
                                        captured = true;
                                        shoot();
                                    }
                                }
                            }, h);
                        } catch (CameraAccessException e) { fail("sessão: " + e.getMessage()); }
                    }
                    @Override public void onConfigureFailed(CameraCaptureSession s) { fail("não consegui configurar a câmera"); }
                }, h);
        } catch (CameraAccessException e) { fail("sessão: " + e.getMessage()); }
    }

    private void lit(CaptureRequest.Builder b) {
        b.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
        b.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
        b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH);   // LED aceso durante a exposição
        b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
    }

    private void shoot() {
        try {
            CaptureRequest.Builder s = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
            s.addTarget(reader.getSurface());
            lit(s);
            s.set(CaptureRequest.JPEG_ORIENTATION, sensorOrientation);
            s.set(CaptureRequest.JPEG_QUALITY, (byte) 85);
            session.capture(s.build(), null, h);
        } catch (CameraAccessException e) { fail("captura: " + e.getMessage()); }
    }

    private void fail(String why) { post("erro", why.getBytes()); }

    /** Sends the result to the bot once, then closes everything. */
    private synchronized void post(String result, byte[] body) {
        if (finished) return;
        finished = true;
        try {
            if (session != null) { session.close(); session = null; }
            if (camera != null) { camera.close(); camera = null; }   // torch goes off here
        } catch (Exception ignored) { }
        try {
            HttpURLConnection c = (HttpURLConnection) new URL("http://127.0.0.1:" + port + "/" + key).openConnection();
            c.setRequestMethod("POST");
            c.setDoOutput(true);
            c.setConnectTimeout(3000);
            c.setReadTimeout(10000);
            c.setFixedLengthStreamingMode(body.length);
            c.setRequestProperty("X-Result", result);
            try (OutputStream o = c.getOutputStream()) { o.write(body); }
            c.getResponseCode();
            c.disconnect();
        } catch (Exception ignored) { }
        runOnUiThread(this::finish);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        try { if (camera != null) camera.close(); } catch (Exception ignored) { }
        if (thread != null) thread.quitSafely();
    }
}
