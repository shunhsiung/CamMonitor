# CamMonitor 專案記憶與變更紀錄 (Project Memory & AI Agent Context)

本文件供後續維護者與 AI Coding Agents 快速掌握專案架構脈絡、已知限制、關鍵設計不變量（Invariants）以及歷次重要修改紀錄。

---

## 一、專案核心脈絡 (Architecture & Invariants)

- **專案名稱**：CamMonitor (`com.a0soft.gphone.camonitor`)
- **產品定位**：將閒置 Android 手機轉為零雲端帳號、點對點加密（WebRTC P2P + E2EE MQTT Signaling）的居家監控攝影機。
- **雙角色設計**：
  - **鏡頭端 (Camera Mode / PA)**：由 `CameraMonitorService`（Foreground Service, `foregroundServiceType="camera"`）管理生命週期、WakeLock/WifiLock、60 秒無人觀看自動休眠（`PAUSED_INACTIVITY`），以及透過 `CameraXVideoCapturer` 提供 720p 視訊、環境光感測自動夜視（`ExtensionMode.NIGHT` 與 Camera2 低光 Fallback）。最多配對與同時連線 **2 台觀看端 (`MAX_PAIRED_VIEWERS = 2`)**。
  - **觀看端 (Viewer Mode / PB)**：接收即時影音串流、支援 90° 硬體紋理旋轉、Aspect Fit/Fill 切換、遠端控制手電筒/夜視模式、雙向對講（Push-to-Talk, PTT，發話時自動壓低本機播放防嘯叫）與雙機電量監控。最多可配對管理 **8 台鏡頭端 (`MAX_PAIRED_CAMERAS = 8`)**。
- **重要測試約束 (Test Invariants)**：
  1. **多語系鍵值與佔位符一致性**：`LocaleResourcesTest.kt` 會嚴格檢查 `app/src/main/res/values/strings.xml` 與 `app/src/main/res/values-b+zh+Hant/strings.xml` 的所有 `<string name="...">` key 集合與 `%1$s` / `%1$d` 格式化佔位符必須 100% 對齊。新增任何 UI 字串時，務必同步更新兩個檔案。
  2. **時間與安全抽象**：測試使用 `TimeProvider` 與 `SecurityRepository` 介面；若在 `SecurityRepository` 新增方法，應提供預設實作（Default implementation）以免破壞既有測試中的 Fake/Mock 類別。

---

## 二、2026-10-19 全面檢視與架構強化紀錄

### 1. 建置與安裝手冊建立
- **新增檔案**：`BUILD_AND_INSTALL_GUIDE_TW.md`（並於 `README_TW.md` 頂部導覽列加入連結）。
- **內容**：涵蓋 Android Studio 圖形化建置、Ubuntu/Linux 純 CLI 命令列建置（OpenJDK 17、Android SDK Command-line Tools、`platforms;android-37`、`build-tools;35.0.0`）、Gradle 編譯與 ADB 手機安裝完整步驟及故障排除。
- **權限修正**：為專案根目錄的 `gradlew` 補上可執行權限 (`chmod +x gradlew`)。

---

### 2. 資安與配對邏輯修正 (Security & Pairing Fixes)
- **修正雙角色配對上限混算 Bug**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/data/security/SecurityRepository.kt` (`DefaultSecurityRepository.addPairedDevice`)
  - **原因**：原先使用 `current.size >= maxLimit` 檢查總裝置數，導致一台曾配對過 $\ge 2$ 台相機的手機切換為鏡頭端時，無法配對任何觀看端（因 `MAX_PAIRED_VIEWERS = 2`）。
  - **修正**：改依 `device.role`（`"VIEWER"` 或 `"CAMERA"`）獨立計算同角色已配對數量，再與 `maxLimit` 比對。
- **OTP 配對階段新增公鑰持有證明 (Proof-of-Possession) 驗簽**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/data/security/SecurityRepository.kt` (`DefaultSecurityRepository.verifyAndDecryptEnvelope`)
  - **原因**：原先在 `isOtpKey = true` 時跳過了 ECDSA 簽章檢查。
  - **修正**：在 AES-256-GCM 解密後，解析 `PairRequest` 或 `PairConfirm` 內嵌的 `pbPublicKeyBase64` / `paPublicKeyBase64`，並驗證 `envelope.signature`，確保發送方確實持有該公鑰對應之私鑰。
- **提升 `PAIR_CONFIRM` 在高丟包網路下的配對成功率**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/ui/pairing/CameraPairingScreen.kt`、`SecurityRepository.kt`
  - **原因**：原先 `addPairedDevice()` 內部立即呼叫 `clearPairingOtp()`，且 `CameraPairingScreen` 僅單次發送 `PAIR_CONFIRM` 後即離開畫面；若訊息丟包，觀看端重試將無法完成配對。
  - **修正**：移除 `addPairedDevice()` 內過早的 `clearPairingOtp()`，並在 `CameraPairingScreen` 發送兩次 `PAIR_CONFIRM` 確認脈衝後才清除 OTP 與跳轉畫面。

---

### 3. MQTT 信令層升級：啟用 TLS (8883) 與多 Broker 容錯移轉 (Failover)
- **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/data/signaling/SignalingClient.kt` (`MqttSignalingClient`)
- **原因**：原先程式碼僅寫死明文 `broker.hivemq.com:1883` (`useSsl = false`)，與 `Specification.md` 記載的 TLS 8883 及雙 Broker 備援不符。
- **修正**：
  1. 定義 `BROKER_ENDPOINTS` 優先序：
     - `broker.hivemq.com:8883` (`useSsl = true`)
     - `broker.hivemq.com:1883` (`useSsl = false`，同叢集防擋埠退避)
     - `broker.emqx.io:8883` (`useSsl = true`，備援叢集)
     - `broker.emqx.io:1883` (`useSsl = false`，備援叢集退避)
  2. 在 `resolveHostAddresses()` 中透過 `InetAddress.getByAddress(host, it.address)` 封裝 `InetSocketAddress`，同時兼具 **IPv4 優先解析**（解決行動網路 IPv6 連不上公開 Broker 問題）與 **TLS SNI 主機名稱憑證驗證**。

---

### 4. 新增自訂 TURN / STUN 伺服器設定（解決跨網 Symmetric NAT 穿透限制）
- **修改檔案**：
  - `app/src/main/java/com/a0soft/gphone/camonitor/data/model/Models.kt`（新增 `TurnServerConfig`）
  - `app/src/main/java/com/a0soft/gphone/camonitor/data/security/SecurityRepository.kt`（新增 `getTurnServerConfig` / `setTurnServerConfig` 並儲存於 `EncryptedSharedPreferences`）
  - `app/src/main/java/com/a0soft/gphone/camonitor/data/webrtc/WebRtcManager.kt`（新增 `buildIceServers()`，動態合併預設 Google STUN 與使用者自訂 TURN 伺服器）
  - `app/src/main/java/com/a0soft/gphone/camonitor/ui/home/HomeScreen.kt`（於 TopAppBar 新增設定按鈕與 TURN 伺服器設定對話框）
  - `app/src/main/res/values/strings.xml` 與 `app/src/main/res/values-b+zh+Hant/strings.xml`（新增雙語字串）

---

### 5. 多執行緒安全、反射死碼清理與日誌 I/O 優化
- **`WebRtcManager` 執行緒安全強化與清理**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/data/webrtc/WebRtcManager.kt`
  - **內容**：
    1. 將 `peerConnections`、`dataChannels`、`remoteAudioTracks` 由 `mutableMapOf` 改為 `ConcurrentHashMap`，防止 WebRTC Signaling 執行緒與主執行緒併發操作引發 `ConcurrentModificationException`。
    2. 移除 `setTorch()` 中 50 多行針對舊版 `org.webrtc.CameraCapturer` 私有欄位的反射死碼，直接委派予 `CameraXVideoCapturer`。
- **`AppLogger` 與 `LogEntry` 效能優化**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/log/AppLogger.kt`、`Models.kt`
  - **內容**：
    1. `LogEntry.format()` 改用執行緒安全的單例 `DateTimeFormatter`，消除每筆日誌重複實例化 `SimpleDateFormat` 的 GC 開銷。
    2. `AppLogger.log()` 改用 `_logsFlow.update { ... }` 確保多執行緒原子更新。
    3. `AppLogger` 磁碟寫入改用常駐 8KB `BufferedWriter` 並配合 `diskLock` 同步保護，取代原先每寫一行就重新開啟/關閉 `FileWriter` 的高 I/O 損耗做法。

---

### 6. UI 狀態保存與 Release R8 縮減配置
- **Activity 重建導航狀態保存**：
  - **檔案**：`app/src/main/java/com/a0soft/gphone/camonitor/MainActivity.kt`
  - **內容**：將 `backStack` 與 `selectedCameraDeviceId` 由 `remember` 改為 `rememberSaveable`，確保切換語言觸發 `recreate()` 或螢幕旋轉時保留當前頁面狀態。
- **啟用 Release R8 最佳化與 ProGuard 規則**：
  - **檔案**：`app/build.gradle.kts`、`app/proguard-rules.pro`
  - **內容**：於 `release` buildType 開啟 `isMinifyEnabled = true` 與 `isShrinkResources = true`，並於 `proguard-rules.pro` 補齊 WebRTC、HiveMQ/Netty/JCTools、CameraX 與資料模型的 Keep 規則。

---

### 7. 單元測試擴充
- `app/src/test/java/com/a0soft/gphone/camonitor/security/MultiCameraPairingTest.kt`：
  - 更新測試 Repository 對齊角色獨立計數邏輯，並新增 `dualRoleDevice_canPairCamerasAndViewersIndependently` 測試。
- `app/src/test/java/com/a0soft/gphone/camonitor/signaling/SignalingStateTest.kt`：
  - 新增 `testBrokerEndpointsPrioritizePrimaryTlsBeforeFallback` 驗證 MQTT TLS 與備援節點順序。

---

## 三、變更檔案總覽 (2026-10-19)

| 狀態 | 檔案路徑 | 變更摘要 |
| :---: | :--- | :--- |
| 新增 | `BUILD_AND_INSTALL_GUIDE_TW.md` | 完整編譯與安裝手冊（Android Studio & Linux CLI） |
| 新增 | `memory.md` | 專案架構快取與 AI Agent 變更追蹤紀錄 |
| 修改 | `README_TW.md` | 頂部導覽列新增編譯與安裝手冊連結 |
| 修改 | `gradlew` | 賦予 `chmod +x` 執行權限 |
| 修改 | `app/build.gradle.kts` | Release 啟用 `isMinifyEnabled` 與 `isShrinkResources` |
| 修改 | `app/proguard-rules.pro` | 補齊 WebRTC、HiveMQ、Netty、CameraX 與 Model 規則 |
| 修改 | `app/src/main/java/.../MainActivity.kt` | `backStack` 與 `selectedCameraDeviceId` 改用 `rememberSaveable` |
| 修改 | `app/src/main/java/.../data/model/Models.kt` | 新增 `TurnServerConfig`；優化 `LogEntry.format()` |
| 修改 | `app/src/main/java/.../data/security/SecurityRepository.kt` | 修正同角色配對上限、新增 OTP 驗簽與 TURN 設定持久化 |
| 修改 | `app/src/main/java/.../data/signaling/SignalingClient.kt` | 支援 MQTT TLS 8883、EMQX 備援與 IPv4 SNI 解析 |
| 修改 | `app/src/main/java/.../data/webrtc/WebRtcManager.kt` | `ConcurrentHashMap` 執行緒安全、載入自訂 TURN、移除廢棄反射 |
| 修改 | `app/src/main/java/.../log/AppLogger.kt` | `_logsFlow.update` 原子更新與常駐 `BufferedWriter` |
| 修改 | `app/src/main/java/.../ui/home/HomeScreen.kt` | 新增自訂 TURN/STUN 伺服器設定按鈕與對話框 |
| 修改 | `app/src/main/java/.../ui/pairing/CameraPairingScreen.kt` | `PAIR_CONFIRM` 雙重發送確認與延後清除 OTP |
| 修改 | `app/src/main/res/values/strings.xml` | 新增自訂 TURN 伺服器英文 UI 字串 |
| 修改 | `app/src/main/res/values-b+zh+Hant/strings.xml` | 新增自訂 TURN 伺服器繁體中文 UI 字串 |
| 修改 | `app/src/test/.../security/MultiCameraPairingTest.kt` | 新增雙角色獨立配對上限單元測試 |
| 修改 | `app/src/test/.../signaling/SignalingStateTest.kt` | 新增 MQTT TLS 與備援節點優先序單元測試 |
