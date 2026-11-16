package andro.marchy;

import android.content.Context;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.Locale;

/**
 * What Android sends for pointer and key input, written to run/input-trace.log while the file run/input-trace
 * exists (from the Linux side: touch $XDG_RUNTIME_DIR/input-trace). For input that misbehaves on a device we do not
 * have: some systems (MagicOS) hide the app's logcat, so the trace goes to a file of the session.
 * Touchscreen moves are left out (too many, and not what is looked for).
 */
final class InputTrace {
    private static final long MAX_BYTES = 512 * 1024;
    private static File flag, log;
    private static long checkedAt = -10000;
    private static boolean on;

    private InputTrace() {}

    static void init(Context ctx) {
        File run = SessionService.runDir(ctx);
        flag = new File(run, "input-trace");
        log = new File(run, "input-trace.log");
    }

    private static boolean enabled() {
        if (flag == null)
            return false;
        long now = SystemClock.uptimeMillis();
        if (now - checkedAt > 2000) {
            checkedAt = now;
            on = flag.exists();
        }
        return on;
    }

    static void motion(String via, MotionEvent e) {
        if (!enabled())
            return;
        int source = e.getSource();
        int action = e.getActionMasked();
        boolean touchscreen = (source & InputDevice.SOURCE_TOUCHSCREEN) == InputDevice.SOURCE_TOUCHSCREEN;
        if (touchscreen || action == MotionEvent.ACTION_HOVER_MOVE)
            return;
        InputDevice d = e.getDevice();
        float histX = 0, histY = 0; // batched samples: relative axes add up over the event's history
        for (int h = 0; h < e.getHistorySize(); h++) {
            histX += e.getHistoricalAxisValue(MotionEvent.AXIS_GESTURE_SCROLL_X_DISTANCE, h);
            histY += e.getHistoricalAxisValue(MotionEvent.AXIS_GESTURE_SCROLL_Y_DISTANCE, h);
        }
        write(String.format(Locale.US,
            "%d %s MOTION dev=\"%s\" src=0x%x action=%s cls=%d ptrs=%d tool=%d hist=%d vscroll=%.3f hscroll=%.3f"
                + " gscrollX=%.3f gscrollY=%.3f relX=%.2f relY=%.2f gdx=%.3f gdy=%.3f histScrollX=%.3f histScrollY=%.3f",
            e.getEventTime(), via, d != null ? d.getName() : "?", source, MotionEvent.actionToString(action),
            e.getClassification(), e.getPointerCount(), e.getToolType(0), e.getHistorySize(),
            e.getAxisValue(MotionEvent.AXIS_VSCROLL), e.getAxisValue(MotionEvent.AXIS_HSCROLL),
            e.getAxisValue(MotionEvent.AXIS_GESTURE_SCROLL_X_DISTANCE),
            e.getAxisValue(MotionEvent.AXIS_GESTURE_SCROLL_Y_DISTANCE),
            e.getAxisValue(MotionEvent.AXIS_RELATIVE_X), e.getAxisValue(MotionEvent.AXIS_RELATIVE_Y),
            e.getAxisValue(MotionEvent.AXIS_GESTURE_X_OFFSET), e.getAxisValue(MotionEvent.AXIS_GESTURE_Y_OFFSET),
            histX, histY));
    }

    static void key(String via, KeyEvent e) {
        if (!enabled())
            return;
        InputDevice d = e.getDevice();
        write(String.format(Locale.US, "%d %s KEY dev=\"%s\" src=0x%x action=%d code=%s meta=0x%x repeat=%d flags=0x%x",
            e.getEventTime(), via, d != null ? d.getName() : "?", e.getSource(), e.getAction(),
            KeyEvent.keyCodeToString(e.getKeyCode()), e.getMetaState(), e.getRepeatCount(), e.getFlags()));
    }

    private static synchronized void write(String line) {
        if (log.length() > MAX_BYTES)
            return;
        try (FileWriter w = new FileWriter(log, true)) {
            w.write(line);
            w.write('\n');
        } catch (IOException ignored) {
        }
    }
}
