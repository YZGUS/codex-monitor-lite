package com.yzgus.codexmonitor;

import android.graphics.Color;

import org.json.JSONException;
import org.json.JSONObject;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;

final class LanTask {
    final String id;
    final String source;
    final String title;
    final String project;
    final String status;
    final Instant lastActivityAt;
    final Long durationMs;

    private LanTask(
            String id,
            String source,
            String title,
            String project,
            String status,
            Instant lastActivityAt,
            Long durationMs
    ) {
        this.id = id;
        this.source = source;
        this.title = title;
        this.project = project;
        this.status = status;
        this.lastActivityAt = lastActivityAt;
        this.durationMs = durationMs;
    }

    static LanTask fromJson(JSONObject value) throws JSONException {
        String timestamp = value.getString("lastActivityAt");
        Long duration = value.isNull("durationMs") ? null : value.optLong("durationMs");
        return new LanTask(
                value.getString("id"),
                value.optString("source", "codex"),
                value.optString("title", "未命名任务"),
                value.optString("project", "Codex"),
                value.getString("status"),
                Instant.parse(timestamp),
                duration
        );
    }

    String statusLabel() {
        switch (status) {
            case "running":
                return "运行中";
            case "needsAttention":
                return "需要你";
            case "awaitingReview":
                return "待查看";
            default:
                return "已查看";
        }
    }

    String activityLabel() {
        switch (status) {
            case "running":
                return "正在运行";
            case "needsAttention":
                return "等待你的操作";
            case "awaitingReview":
                return "任务已完成";
            default:
                return "已查看";
        }
    }

    int statusColor() {
        switch (status) {
            case "running":
                return Color.rgb(49, 215, 122);
            case "needsAttention":
                return Color.rgb(255, 171, 51);
            case "awaitingReview":
                return Color.rgb(95, 138, 196);
            default:
                return Color.rgb(139, 151, 161);
        }
    }

    String relativeTime(Instant now) {
        long seconds = Math.max(0, Duration.between(lastActivityAt, now).getSeconds());
        if (seconds < 60) return "刚刚";
        if (seconds < 3_600) return String.format(Locale.ROOT, "%d 分钟前", seconds / 60);
        if (seconds < 86_400) return String.format(Locale.ROOT, "%d 小时前", seconds / 3_600);
        return String.format(Locale.ROOT, "%d 天前", seconds / 86_400);
    }

    String durationLabel() {
        if (durationMs == null) return "—";
        long totalSeconds = Math.max(0, durationMs / 1_000);
        long hours = totalSeconds / 3_600;
        long minutes = (totalSeconds % 3_600) / 60;
        long seconds = totalSeconds % 60;
        if (hours > 0) return String.format(Locale.ROOT, "%dh %02dm", hours, minutes);
        if (minutes > 0) return String.format(Locale.ROOT, "%dm %02ds", minutes, seconds);
        return String.format(Locale.ROOT, "%ds", seconds);
    }
}
