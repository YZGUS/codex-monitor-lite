package com.yzgus.codexmonitor;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class LanDiscoveryClient {
    interface Listener {
        void onConnectionState(String label, boolean connected);
        void onSnapshot(List<LanTask> tasks);
    }

    private static final String SERVICE_TYPE = "_codexmonitor._tcp.";

    private final NsdManager nsdManager;
    private final WifiManager.MulticastLock multicastLock;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService networkExecutor = Executors.newSingleThreadExecutor();
    private final Listener listener;

    private volatile boolean active;
    private volatile int generation;
    private boolean resolvingOrConnected;
    private NsdManager.DiscoveryListener discoveryListener;
    private volatile Socket socket;
    private String pairingCode = "";

    LanDiscoveryClient(Context context, Listener listener) {
        Context appContext = context.getApplicationContext();
        this.nsdManager = (NsdManager) appContext.getSystemService(Context.NSD_SERVICE);
        WifiManager wifiManager = (WifiManager) appContext.getSystemService(Context.WIFI_SERVICE);
        this.multicastLock = wifiManager.createMulticastLock("codex-monitor-discovery");
        this.multicastLock.setReferenceCounted(false);
        this.listener = listener;
    }

    void start(String code) {
        stop();
        pairingCode = normalizeCode(code);
        if (pairingCode.length() != 10) {
            postState("请输入有效连接码", false);
            return;
        }

        active = true;
        generation += 1;
        resolvingOrConnected = false;
        if (!multicastLock.isHeld()) multicastLock.acquire();
        discover(generation);
    }

    void stop() {
        active = false;
        generation += 1;
        resolvingOrConnected = false;
        stopDiscovery();
        closeSocket();
        if (multicastLock.isHeld()) multicastLock.release();
    }

    void destroy() {
        stop();
        networkExecutor.shutdownNow();
    }

    private void discover(int runGeneration) {
        postState("正在查找 Mac", false);
        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onDiscoveryStarted(String serviceType) {
                if (isCurrent(runGeneration)) postState("正在查找 Mac", false);
            }

            @Override
            public void onServiceFound(NsdServiceInfo serviceInfo) {
                if (!isCurrent(runGeneration) || resolvingOrConnected) return;
                resolvingOrConnected = true;
                postState("正在连接", false);
                resolve(serviceInfo, runGeneration);
            }

            @Override
            public void onServiceLost(NsdServiceInfo serviceInfo) {
                // The open socket is authoritative and will report its own disconnect.
            }

            @Override
            public void onDiscoveryStopped(String serviceType) {
            }

            @Override
            public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                if (isCurrent(runGeneration)) postState("无法搜索局域网设备", false);
            }

            @Override
            public void onStopDiscoveryFailed(String serviceType, int errorCode) {
            }
        };

        try {
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener);
        } catch (RuntimeException error) {
            postState("无法搜索局域网设备", false);
        }
    }

    @SuppressWarnings("deprecation")
    private void resolve(NsdServiceInfo serviceInfo, int runGeneration) {
        nsdManager.resolveService(serviceInfo, new NsdManager.ResolveListener() {
            @Override
            public void onResolveFailed(NsdServiceInfo failedService, int errorCode) {
                if (!isCurrent(runGeneration)) return;
                resolvingOrConnected = false;
                postState("未连接，点击重试", false);
            }

            @Override
            public void onServiceResolved(NsdServiceInfo resolvedService) {
                if (!isCurrent(runGeneration)) return;
                networkExecutor.execute(() -> connectAndRead(resolvedService, runGeneration));
            }
        });
    }

    @SuppressWarnings("deprecation")
    private void connectAndRead(NsdServiceInfo serviceInfo, int runGeneration) {
        boolean receivedSnapshot = false;
        try {
            Socket nextSocket = new Socket();
            socket = nextSocket;
            nextSocket.connect(new InetSocketAddress(serviceInfo.getHost(), serviceInfo.getPort()), 5_000);

            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                    nextSocket.getOutputStream(), StandardCharsets.UTF_8
            ));
            JSONObject auth = new JSONObject();
            auth.put("type", "authenticate");
            auth.put("pairingCode", pairingCode);
            writer.write(auth.toString());
            writer.newLine();
            writer.flush();

            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    nextSocket.getInputStream(), StandardCharsets.UTF_8
            ));
            String line;
            while (isCurrent(runGeneration) && (line = reader.readLine()) != null) {
                List<LanTask> tasks = parseSnapshot(line);
                if (tasks == null) continue;
                receivedSnapshot = true;
                postState("已连接 Mac", true);
                postSnapshot(tasks);
            }
        } catch (Exception ignored) {
        } finally {
            closeSocket();
            if (isCurrent(runGeneration)) {
                resolvingOrConnected = false;
                postState(
                        receivedSnapshot ? "连接已断开，点击重试" : "连接失败，请检查连接码",
                        false
                );
            }
        }
    }

    private List<LanTask> parseSnapshot(String line) {
        try {
            JSONObject root = new JSONObject(line);
            if (!"snapshot".equals(root.optString("type")) || root.optInt("schemaVersion") != 1) {
                return null;
            }
            JSONArray values = root.getJSONArray("tasks");
            List<LanTask> tasks = new ArrayList<>(values.length());
            for (int index = 0; index < values.length(); index++) {
                tasks.add(LanTask.fromJson(values.getJSONObject(index)));
            }
            return tasks;
        } catch (Exception ignored) {
            return null;
        }
    }

    private boolean isCurrent(int runGeneration) {
        return active && generation == runGeneration;
    }

    private void postState(String label, boolean connected) {
        mainHandler.post(() -> listener.onConnectionState(label, connected));
    }

    private void postSnapshot(List<LanTask> tasks) {
        mainHandler.post(() -> listener.onSnapshot(tasks));
    }

    private void stopDiscovery() {
        NsdManager.DiscoveryListener current = discoveryListener;
        discoveryListener = null;
        if (current == null) return;
        try {
            nsdManager.stopServiceDiscovery(current);
        } catch (RuntimeException ignored) {
        }
    }

    private void closeSocket() {
        Socket current = socket;
        socket = null;
        if (current == null) return;
        try {
            current.close();
        } catch (Exception ignored) {
        }
    }

    static String normalizeCode(String code) {
        return code == null
                ? ""
                : code.replace("-", "").replace(" ", "").toUpperCase(Locale.ROOT);
    }
}
