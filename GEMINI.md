# GEMINI.md — CamMonitor AI Agent 開發與維護指南

本文件為 AI Coding Agents（如 Gemini / Antigravity）的專案層級核心設定與上下文指南。在進行任何程式碼修改、問題排查或功能擴充前，請務必閱讀並遵循以下規範。

---

## 1. 專案總覽與設計哲學

- **專案名稱**：**CamMonitor** (`com.a0soft.gphone.camonitor`)
- **核心目標**：將閒置 Android 手機轉化為**零雲端帳號、點對點端對端加密 (P2P E2EE)** 的居家安全監控攝影機。
- **硬體保護原則 (Hardware Longevity Philosophy)**：
  - 專案定位為**按需即時監控 (On-Demand Live Monitor)**。除非使用者明確要求，否則**請勿預設加入 24/7 全時錄影或高負載常駐 AI 物件偵測**，以防止備用手機過熱、電池膨脹與感光元件加速老化。
  - **OLED 防烙印黑屏**：鏡頭端閒置 60 秒自動降至極低亮度全黑畫面，點擊任意處喚醒。
  - **自動休眠待命 (`PAUSED_INACTIVITY`)**：0 位觀看端連線滿 60 秒時，自動釋放相機硬體感測器；收到合法 WebRTC `Offer` 時自動喚醒重啟鏡頭。

---

## 2. 專案重要文件索引

進行開發或回答問題時，請優先參考並同步維護以下文件：

| 文件檔案 | 用途說明 |
| :--- | :--- |
| [`memory.md`](memory.md) | **歷次變更紀錄與追蹤日誌**（每次重大修改後請同步更新此檔案） |
| [`Specification.md`](Specification.md) | 系統完整規格書（安全架構、UI 規格、WebRTC/MQTT 協定） |
| [`BUILD_AND_INSTALL_GUIDE_TW.md`](BUILD_AND_INSTALL_GUIDE_TW.md) | 編譯、環境安裝（Android Studio / Linux CLI）與 ADB 部署手冊 |
| [`README.md`](README.md) / [`README_TW.md`](README_TW.md) | 英文與繁體中文專案說明書 |

---

## 3. 核心程式碼結構地圖

```text
app/src/main/java/com/a0soft/gphone/camonitor/
├── CamMonitorApp.kt                 # Application 入口與單例依賴注入容器
├── MainActivity.kt                  # 單一 Activity + rememberSaveable 畫面導航管理
├── service/
│   └── CameraMonitorService.kt      # 鏡頭端前景服務 (camera type)、WakeLock/WifiLock、60s 待命計時
├── data/
│   ├── model/Models.kt              # 配對 Payload、加密信封、SignalingMessage、ControlCommand、TurnServerConfig
│   ├── security/
│   │   ├── CryptoUtils.kt           # ECDSA P-256 (AndroidKeyStore/Software)、ECDH、HKDF-SHA256、AES-256-GCM
│   │   └── SecurityRepository.kt    # 白名單管理 (8 Camera / 2 Viewer)、信封加解密驗簽、防重放、偏好設定
│   ├── signaling/
│   │   └── SignalingClient.kt       # MqttSignalingClient (TLS 8883 優先、HiveMQ/EMQX 雙叢集備援、IPv4 優先)
│   ├── webrtc/
│   │   └── WebRtcManager.kt         # WebRTC PeerConnection、DataChannel、PTT 對講、STUN/自訂 TURN 整合
│   └── camera/
│       ├── CameraXVideoCapturer.kt  # CameraX 擷取、環境光感測防抖滯後 (<10 lux / >25 lux)、Night Extension & Camera2 低光 Fallback
│       └── TorchManager.kt          # 遠端手電筒控制
├── log/
│   └── AppLogger.kt                 # 非同步滾動式檔案日誌 (2MB x 3 份，BufferedWriter + 記憶體 StateFlow)
└── ui/
    ├── home/HomeScreen.kt           # 首頁模式選擇、相機選擇、語言切換、自訂 TURN 伺服器設定
    ├── pairing/                     # CameraPairingScreen (QR 產生) & ViewerPairingScreen (ZXing 掃描)
    ├── camera/CameraModeScreen.kt   # 鏡頭端 HUD、OLED 黑屏保護、待機重啟介面
    ├── viewer/ViewerModeScreen.kt   # 觀看端播放器 (Aspect Fit/Fill、90° 旋轉)、PTT 對講、夜視三段切換、雙機電量
    ├── devices/ManageDevicesScreen.kt # 已配對裝置管理與撤銷授權
    ├── log/LogViewerScreen.kt       # 內建日誌檢視器與 FileProvider 分享匯出
    └── about/AboutScreen.kt         # 關於頁面與版本資訊
```

---

## 4. 開發規範與測試不變量（AI Agent 必讀規則）

修改程式碼時，**必須嚴格遵守以下不變量**以確保所有單元測試與架構正常運作：

1. **多語系字串 100% 同步 (`LocaleResourcesTest`)**：
   - 單元測試 [`LocaleResourcesTest.kt`](app/src/test/java/com/a0soft/gphone/camonitor/i18n/LocaleResourcesTest.kt) 會嚴格比對 `app/src/main/res/values/strings.xml` 與 `app/src/main/res/values-b+zh+Hant/strings.xml`。
   - **規則**：新增、修改或刪除任何字串時，兩份 XML 的 `name` key 集合與格式化佔位符（如 `%1$s`、`%1$d`）順序與數量**必須完全一致**。
2. **`SecurityRepository` 介面相容性**：
   - 多個單元測試（如 [`MultiCameraPairingTest.kt`](app/src/test/java/com/a0soft/gphone/camonitor/security/MultiCameraPairingTest.kt)、[`ViewerAudioSettingsTest.kt`](app/src/test/java/com/a0soft/gphone/camonitor/security/ViewerAudioSettingsTest.kt)）有實作獨立的 Fake `SecurityRepository`。
   - **規則**：在 `SecurityRepository` 介面新增方法時，請提供預設實作（Default Method），避免破壞測試類別編譯。
3. **角色獨立配對上限**：
   - `addPairedDevice(device, maxLimit)` 必須依 `device.role`（`"CAMERA"` 上限 8 台、`"VIEWER"` 上限 2 台）分別計算數量，不可將兩種角色混算。
4. **執行緒安全 (Thread Safety)**：
   - `WebRtcManager` 中的連線狀態集合（`peerConnections`、`dataChannels`、`remoteAudioTracks`、`pendingRemoteIceCandidates`）皆會跨 WebRTC 原生執行緒與主執行緒存取，必須維持使用 `ConcurrentHashMap` 或同步集合。
5. **持續維護記憶檔 (`memory.md`)**：
   - 每次完成功能新增、Bug 修復或架構調整後，請將變更背景與修改檔案清單追加記錄至 [`memory.md`](memory.md)。

---

## 5. 近期重大架構強化摘要 (2026-10-19)

詳細紀錄請參閱 [`memory.md`](memory.md)，重點摘要如下：

1. **配對與資安強化**：
   - 修正 `DefaultSecurityRepository.addPairedDevice()` 混算 Camera/Viewer 配對上限的 Bug。
   - 新增 OTP 交握階段對 `PairRequest` / `PairConfirm` 內嵌公鑰的 ECDSA 持有證明驗簽（Proof-of-Possession）。
   - `CameraPairingScreen` 新增 `PAIR_CONFIRM` 雙重脈衝發送並延後清除 OTP，提升不穩定網路下的配對成功率。
2. **MQTT 信令 TLS 8883 與多節點 Failover**：
   - `MqttSignalingClient` 優先連線 `broker.hivemq.com:8883 (TLS)`，並支援 `1883` 與備援 `broker.emqx.io` (`8883`/`1883`) 自動切換；同時保留 IPv4 優先解析與 TLS SNI 驗證。
3. **自訂 TURN / STUN 伺服器支援**：
   - 新增 `TurnServerConfig`，於 `HomeScreen` 頂部工具列提供設定對話框，並在 `WebRtcManager.buildIceServers()` 動態掛載，解決跨電信行動網路對稱型 NAT (Symmetric NAT) 穿透問題。
4. **多執行緒與日誌 I/O 優化**：
   - `WebRtcManager` 全面改用 `ConcurrentHashMap` 並移除 `setTorch()` 舊版反射死碼。
   - `AppLogger` 改用 `_logsFlow.update` 原子更新、常駐 `BufferedWriter` 與單例 `DateTimeFormatter`。
5. **UI 狀態保存與 Release R8 最佳化**：
   - `MainActivity` 導航 `backStack` 與 `selectedCameraDeviceId` 改用 `rememberSaveable`。
   - `app/build.gradle.kts` 啟用 Release `isMinifyEnabled = true` 與 `isShrinkResources = true`，並完善 `app/proguard-rules.pro`。
