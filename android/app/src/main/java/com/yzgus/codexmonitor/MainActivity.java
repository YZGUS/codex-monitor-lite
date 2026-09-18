package com.yzgus.codexmonitor;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

public final class MainActivity extends Activity implements LanDiscoveryClient.Listener {
    private static final int BACKGROUND = Color.rgb(16, 24, 32);
    private static final int SURFACE = Color.rgb(24, 35, 44);
    private static final int SURFACE_SELECTED = Color.rgb(239, 243, 246);
    private static final int PRIMARY = Color.rgb(242, 245, 247);
    private static final int SECONDARY = Color.rgb(154, 166, 175);
    private static final int GREEN = Color.rgb(49, 215, 122);
    private static final String PREFS = "codex_monitor";
    private static final String PAIRING_CODE = "pairing_code";

    private final List<LanTask> allTasks = new ArrayList<>();
    private final List<LanTask> visibleTasks = new ArrayList<>();

    private SharedPreferences preferences;
    private LanDiscoveryClient client;
    private TaskAdapter adapter;
    private LinearLayout pairingCard;
    private EditText pairingInput;
    private TextView connectionDot;
    private TextView connectionLabel;
    private TextView changeConnection;
    private TextView emptyState;
    private ListView taskList;
    private TextView[] filterButtons;
    private String selectedStatus = "running";
    private boolean isStarted;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(BACKGROUND);
        getWindow().setNavigationBarColor(BACKGROUND);

        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        client = new LanDiscoveryClient(this, this);
        setContentView(makeContentView());
        updateFilters();
    }

    @Override
    protected void onStart() {
        super.onStart();
        isStarted = true;
        String savedCode = preferences.getString(PAIRING_CODE, "");
        if (savedCode != null && !savedCode.isEmpty()) {
            pairingInput.setText(savedCode);
            connectToMac();
        } else {
            showConnectionState("等待配对", false);
        }
    }

    @Override
    protected void onStop() {
        isStarted = false;
        client.stop();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        client.destroy();
        super.onDestroy();
    }

    @Override
    public void onConnectionState(String label, boolean connected) {
        showConnectionState(label, connected);
        pairingCard.setVisibility(connected ? View.GONE : View.VISIBLE);
        changeConnection.setVisibility(connected ? View.VISIBLE : View.GONE);
    }

    @Override
    public void onSnapshot(List<LanTask> tasks) {
        allTasks.clear();
        allTasks.addAll(tasks);
        applyFilter();
    }

    private View makeContentView() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BACKGROUND);
        root.setPadding(dp(16), dp(12), dp(16), dp(10));

        root.addView(makeHeader(), matchWrap());
        pairingCard = makePairingCard();
        LinearLayout.LayoutParams pairingParams = matchWrap();
        pairingParams.topMargin = dp(12);
        root.addView(pairingCard, pairingParams);

        LinearLayout filters = makeFilters();
        LinearLayout.LayoutParams filterParams = matchWrap();
        filterParams.topMargin = dp(12);
        root.addView(filters, filterParams);

        FrameLayout content = new FrameLayout(this);
        LinearLayout.LayoutParams contentParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
        );
        contentParams.topMargin = dp(10);

        taskList = new ListView(this);
        taskList.setBackgroundColor(Color.TRANSPARENT);
        taskList.setDivider(null);
        taskList.setDividerHeight(0);
        taskList.setSelector(android.R.color.transparent);
        taskList.setVerticalScrollBarEnabled(false);
        taskList.setClipToPadding(false);
        taskList.setPadding(0, 0, 0, dp(2));
        adapter = new TaskAdapter();
        taskList.setAdapter(adapter);
        content.addView(taskList, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        emptyState = text("暂无运行中的任务", 14, SECONDARY, Typeface.NORMAL);
        emptyState.setGravity(Gravity.CENTER);
        content.addView(emptyState, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        root.addView(content, contentParams);

        TextView footer = text("局域网 · 最近 24h", 11, SECONDARY, Typeface.NORMAL);
        footer.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        root.addView(footer, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(28)
        ));
        return root;
    }

    private View makeHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView title = text("Codex", 22, PRIMARY, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(42), 1f));

        connectionDot = text("●", 11, SECONDARY, Typeface.NORMAL);
        connectionDot.setGravity(Gravity.CENTER);
        header.addView(connectionDot, new LinearLayout.LayoutParams(dp(18), dp(42)));

        connectionLabel = text("等待配对", 12, SECONDARY, Typeface.NORMAL);
        connectionLabel.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(connectionLabel, wrapWrap());

        changeConnection = text("更换", 12, PRIMARY, Typeface.BOLD);
        changeConnection.setGravity(Gravity.CENTER);
        changeConnection.setPadding(dp(12), 0, 0, 0);
        changeConnection.setVisibility(View.GONE);
        changeConnection.setOnClickListener(view -> {
            client.stop();
            pairingCard.setVisibility(View.VISIBLE);
            changeConnection.setVisibility(View.GONE);
            showConnectionState("等待重新连接", false);
            pairingInput.requestFocus();
        });
        header.addView(changeConnection, new LinearLayout.LayoutParams(dp(52), dp(42)));
        return header;
    }

    private LinearLayout makePairingCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(13), dp(14), dp(14));
        card.setBackground(rounded(SURFACE, 14));

        card.addView(text("连接 Mac", 15, PRIMARY, Typeface.BOLD), matchWrap());
        TextView detail = text("在 Mac 菜单栏面板点击手机图标，输入显示的连接码。", 12, SECONDARY, Typeface.NORMAL);
        detail.setPadding(0, dp(4), 0, dp(10));
        card.addView(detail, matchWrap());

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        pairingInput = new EditText(this);
        pairingInput.setSingleLine(true);
        pairingInput.setTextColor(PRIMARY);
        pairingInput.setHintTextColor(Color.rgb(104, 119, 130));
        pairingInput.setTextSize(15);
        pairingInput.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        pairingInput.setHint("XXXXX-XXXXX");
        pairingInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        pairingInput.setFilters(new InputFilter[]{new InputFilter.AllCaps(), new InputFilter.LengthFilter(11)});
        pairingInput.setImeOptions(EditorInfo.IME_ACTION_DONE);
        pairingInput.setPadding(dp(12), 0, dp(12), 0);
        GradientDrawable inputBackground = rounded(Color.rgb(18, 28, 36), 10);
        inputBackground.setStroke(dp(1), Color.rgb(55, 70, 81));
        pairingInput.setBackground(inputBackground);
        pairingInput.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                connectToMac();
                return true;
            }
            return false;
        });
        row.addView(pairingInput, new LinearLayout.LayoutParams(0, dp(46), 1f));

        Button connect = new Button(this);
        connect.setText("连接");
        connect.setTextSize(13);
        connect.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        connect.setTextColor(Color.rgb(9, 42, 25));
        connect.setAllCaps(false);
        connect.setBackground(rounded(GREEN, 10));
        connect.setOnClickListener(view -> connectToMac());
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(dp(76), dp(46));
        buttonParams.leftMargin = dp(8);
        row.addView(connect, buttonParams);
        card.addView(row, matchWrap());
        return card;
    }

    private LinearLayout makeFilters() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(dp(3), dp(3), dp(3), dp(3));
        row.setBackground(rounded(Color.rgb(12, 20, 27), 12));

        String[] labels = {"运行中", "需要你", "待查看"};
        String[] statuses = {"running", "needsAttention", "awaitingReview"};
        filterButtons = new TextView[labels.length];
        for (int index = 0; index < labels.length; index++) {
            final String status = statuses[index];
            TextView button = text(labels[index], 12, PRIMARY, Typeface.BOLD);
            button.setGravity(Gravity.CENTER);
            button.setOnClickListener(view -> {
                selectedStatus = status;
                applyFilter();
            });
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(40), 1f);
            if (index > 0) params.leftMargin = dp(3);
            row.addView(button, params);
            filterButtons[index] = button;
        }
        return row;
    }

    private void connectToMac() {
        String rawCode = pairingInput.getText().toString().trim();
        String normalized = LanDiscoveryClient.normalizeCode(rawCode);
        if (normalized.length() != 10) {
            showConnectionState("连接码格式不正确", false);
            return;
        }
        String formatted = normalized.substring(0, 5) + "-" + normalized.substring(5);
        pairingInput.setText(formatted);
        pairingInput.setSelection(formatted.length());
        preferences.edit().putString(PAIRING_CODE, formatted).apply();
        hideKeyboard();
        if (isStarted) client.start(formatted);
    }

    private void showConnectionState(String label, boolean connected) {
        connectionLabel.setText(label);
        connectionDot.setTextColor(connected ? GREEN : SECONDARY);
    }

    private void applyFilter() {
        visibleTasks.clear();
        for (LanTask task : allTasks) {
            if (selectedStatus.equals(task.status)) visibleTasks.add(task);
        }
        adapter.notifyDataSetChanged();
        updateFilters();

        boolean empty = visibleTasks.isEmpty();
        taskList.setVisibility(empty ? View.GONE : View.VISIBLE);
        emptyState.setVisibility(empty ? View.VISIBLE : View.GONE);
        if ("running".equals(selectedStatus)) emptyState.setText("暂无运行中的任务");
        if ("needsAttention".equals(selectedStatus)) emptyState.setText("暂无需要处理的任务");
        if ("awaitingReview".equals(selectedStatus)) emptyState.setText("暂无待查看的任务");
    }

    private void updateFilters() {
        if (filterButtons == null) return;
        String[] statuses = {"running", "needsAttention", "awaitingReview"};
        String[] labels = {"运行中", "需要你", "待查看"};
        for (int index = 0; index < filterButtons.length; index++) {
            int count = 0;
            for (LanTask task : allTasks) {
                if (statuses[index].equals(task.status)) count++;
            }
            boolean selected = statuses[index].equals(selectedStatus);
            TextView button = filterButtons[index];
            button.setText(labels[index] + "  " + count);
            button.setTextColor(selected ? Color.rgb(27, 35, 41) : PRIMARY);
            button.setBackground(rounded(selected ? SURFACE_SELECTED : SURFACE, 9));
        }
    }

    private void hideKeyboard() {
        InputMethodManager manager = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        manager.hideSoftInputFromWindow(pairingInput.getWindowToken(), 0);
        pairingInput.clearFocus();
    }

    private TextView text(String value, float size, int color, int style) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(Typeface.DEFAULT, style);
        view.setIncludeFontPadding(false);
        return view;
    }

    private GradientDrawable rounded(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private LinearLayout.LayoutParams wrapWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private final class TaskAdapter extends BaseAdapter {
        @Override
        public int getCount() {
            return visibleTasks.size();
        }

        @Override
        public LanTask getItem(int position) {
            return visibleTasks.get(position);
        }

        @Override
        public long getItemId(int position) {
            return getItem(position).id.hashCode();
        }

        @Override
        public boolean isEnabled(int position) {
            return false;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            TaskRowHolder holder;
            if (convertView == null) {
                holder = new TaskRowHolder();
                convertView = holder.wrapper;
                convertView.setTag(holder);
            } else {
                holder = (TaskRowHolder) convertView.getTag();
            }
            holder.bind(getItem(position));
            return convertView;
        }
    }

    private final class TaskRowHolder {
        final LinearLayout wrapper = new LinearLayout(MainActivity.this);
        final TextView dot;
        final TextView title;
        final TextView relativeTime;
        final TextView activity;
        final TextView status;
        final TextView metadata;

        TaskRowHolder() {
            wrapper.setOrientation(LinearLayout.VERTICAL);
            wrapper.setPadding(0, 0, 0, dp(8));

            LinearLayout card = new LinearLayout(MainActivity.this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(11), dp(12), dp(11));
            card.setBackground(rounded(SURFACE, 13));
            wrapper.addView(card, matchWrap());

            LinearLayout top = new LinearLayout(MainActivity.this);
            top.setOrientation(LinearLayout.HORIZONTAL);
            top.setGravity(Gravity.CENTER_VERTICAL);
            dot = text("●", 13, GREEN, Typeface.NORMAL);
            top.addView(dot, new LinearLayout.LayoutParams(dp(20), dp(24)));
            title = text("", 14, PRIMARY, Typeface.BOLD);
            title.setSingleLine(true);
            title.setEllipsize(android.text.TextUtils.TruncateAt.END);
            top.addView(title, new LinearLayout.LayoutParams(0, dp(24), 1f));
            relativeTime = text("", 11, SECONDARY, Typeface.NORMAL);
            relativeTime.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
            top.addView(relativeTime, new LinearLayout.LayoutParams(dp(74), dp(24)));
            card.addView(top, matchWrap());

            LinearLayout middle = new LinearLayout(MainActivity.this);
            middle.setOrientation(LinearLayout.HORIZONTAL);
            middle.setPadding(dp(20), dp(4), 0, 0);
            activity = text("", 12, SECONDARY, Typeface.NORMAL);
            activity.setSingleLine(true);
            activity.setEllipsize(android.text.TextUtils.TruncateAt.END);
            middle.addView(activity, new LinearLayout.LayoutParams(0, dp(21), 1f));
            status = text("", 11, GREEN, Typeface.BOLD);
            status.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
            middle.addView(status, new LinearLayout.LayoutParams(dp(58), dp(21)));
            card.addView(middle, matchWrap());

            metadata = text("", 11, SECONDARY, Typeface.NORMAL);
            metadata.setSingleLine(true);
            metadata.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);
            metadata.setPadding(dp(20), dp(5), 0, 0);
            card.addView(metadata, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(23)
            ));
        }

        void bind(LanTask task) {
            dot.setTextColor(task.statusColor());
            title.setText(task.title);
            relativeTime.setText(task.relativeTime(Instant.now()));
            activity.setText(task.activityLabel());
            status.setText(task.statusLabel());
            status.setTextColor(task.statusColor());
            metadata.setText(task.project + "   ·   " + task.durationLabel());
        }
    }
}
