package com.j4.launcher;

import android.app.Activity;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextClock;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Minimal home screen: clock, date, battery, and a plain text list of apps.
 * No icons, no images, no AndroidX, no background receivers; the app list is
 * rebuilt on every resume and dropped on stop, so almost nothing stays in RAM.
 */
public class MainActivity extends Activity {
    private static final int FG = Color.rgb(235, 235, 235);
    private static final int DIM = Color.rgb(140, 140, 140);

    private static final class App {
        final String label, pkg, cls;
        App(String l, String p, String c) { label = l; pkg = p; cls = c; }
    }

    private List<App> apps = new ArrayList<>();
    private TextView battery;
    private BaseAdapter adapter;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        float d = getResources().getDisplayMetrics().density;
        int pad = (int) (20 * d);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);
        root.setPadding(pad, (int) (36 * d), pad, 0);

        TextClock time = new TextClock(this);
        time.setFormat24Hour("HH:mm");
        time.setFormat12Hour("HH:mm");
        time.setTextSize(54);
        time.setTextColor(FG);
        time.setTypeface(android.graphics.Typeface.create("sans-serif-light", 0));
        root.addView(time);

        TextClock date = new TextClock(this);
        date.setFormat24Hour("EEEE, d 'de' MMMM");
        date.setFormat12Hour("EEEE, d 'de' MMMM");
        date.setTextSize(16);
        date.setTextColor(DIM);
        root.addView(date);

        battery = new TextView(this);
        battery.setTextSize(14);
        battery.setTextColor(DIM);
        battery.setPadding(0, (int) (2 * d), 0, (int) (16 * d));
        root.addView(battery);

        ListView list = new ListView(this);
        list.setDivider(null);
        list.setVerticalScrollBarEnabled(false);
        list.setOverScrollMode(View.OVER_SCROLL_NEVER);
        adapter = new BaseAdapter() {
            public int getCount() { return apps.size(); }
            public Object getItem(int i) { return apps.get(i); }
            public long getItemId(int i) { return i; }
            public View getView(int i, View v, ViewGroup p) {
                TextView t = (TextView) v;
                if (t == null) {
                    t = new TextView(MainActivity.this);
                    t.setTextSize(22);
                    t.setTextColor(FG);
                    t.setSingleLine(true);
                    t.setGravity(Gravity.CENTER_VERTICAL);
                    t.setMinHeight((int) (52 * MainActivity.this.getResources().getDisplayMetrics().density));
                }
                t.setText(apps.get(i).label);
                return t;
            }
        };
        list.setAdapter(adapter);
        list.setOnItemClickListener((p, v, i, id) -> launch(apps.get(i)));
        list.setOnItemLongClickListener((p, v, i, id) -> {
            // long press: app info (uninstall / force stop / permissions)
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + apps.get(i).pkg)));
            return true;
        });
        root.addView(list, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        loadApps();
        showBattery();
    }

    @Override
    protected void onStop() {
        super.onStop();
        apps = new ArrayList<>();   // free the list while an app is in front
        adapter.notifyDataSetChanged();
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);       // Home pressed again: scroll back to the top
        if (getWindow().getDecorView() instanceof ViewGroup) {
            ListView l = findList((ViewGroup) getWindow().getDecorView());
            if (l != null) l.setSelection(0);
        }
    }

    @Override
    public void onBackPressed() { /* this is the home screen: nothing to go back to */ }

    private ListView findList(ViewGroup g) {
        for (int i = 0; i < g.getChildCount(); i++) {
            View c = g.getChildAt(i);
            if (c instanceof ListView) return (ListView) c;
            if (c instanceof ViewGroup) {
                ListView l = findList((ViewGroup) c);
                if (l != null) return l;
            }
        }
        return null;
    }

    private void loadApps() {
        Intent q = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> found = getPackageManager().queryIntentActivities(q, 0);
        List<App> out = new ArrayList<>();
        for (ResolveInfo r : found) {
            if (getPackageName().equals(r.activityInfo.packageName)) continue;
            out.add(new App(String.valueOf(r.loadLabel(getPackageManager())),
                    r.activityInfo.packageName, r.activityInfo.name));
        }
        Collections.sort(out, new Comparator<App>() {
            public int compare(App a, App b) { return a.label.compareToIgnoreCase(b.label); }
        });
        apps = out;
        adapter.notifyDataSetChanged();
    }

    private void showBattery() {
        Intent s = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (s == null) { battery.setText(""); return; }
        int level = s.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = s.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        int plugged = s.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        int temp = s.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0);
        battery.setText((level * 100 / scale) + "%" + (plugged != 0 ? " ⚡" : "")
                + "  ·  " + (temp / 10) + "°C");
    }

    private void launch(App a) {
        Intent i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .setClassName(a.pkg, a.cls).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try { startActivity(i); } catch (Exception ignored) { }
    }
}
