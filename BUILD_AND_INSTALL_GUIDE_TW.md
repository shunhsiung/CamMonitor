# CamMonitor 建置與安裝手冊 (Build & Install Guide)

本手冊提供在 Linux (以 Ubuntu 為主) 或各作業系統環境下，編譯、建置與安裝 **CamMonitor** 的完整步驟。

---

## 目錄

- [一、系統與建置需求規格](#一系統與建置需求規格)
- [二、方法一：使用 Android Studio 建置（推薦）](#二方法一使用-android-studio-建置推薦)
- [三、方法二：Linux 純終端機命令列 (CLI) 建置](#三方法二linux-純終端機命令列-cli-建置)
  - [1. 安裝系統相依套件與 OpenJDK 17](#1-安裝系統相依套件與-openjdk-17)
  - [2. 下載與安裝 Android SDK 命令列工具](#2-下載與安裝-android-sdk-命令列工具)
  - [3. 設定環境變數](#3-設定環境變數)
  - [4. 下載 Android 平台與建置元件 (API 37)](#4-下載-android-平台與建置元件-api-37)
- [四、專案編譯流程](#四專案編譯流程)
  - [1. 賦予 Gradle 執行權限](#1-賦予-gradle-執行權限)
  - [2. 執行單元測試](#2-執行單元測試)
  - [3. 編譯 Debug 版 APK](#3-編譯-debug-版-apk)
  - [4. 編譯 Release 正式簽署版 APK（可選）](#4-編譯-release-正式簽署版-apk可選)
- [五、安裝至 Android 手機](#五安裝至-android-手機)
  - [1. 開啟手機端 USB 偵錯](#1-開啟手機端-usb-偵錯)
  - [2. 驗證連線並安裝 APK](#2-驗證連線並安裝-apk)
- [六、常見問題與故障排除 (Troubleshooting)](#六常見問題與故障排除-troubleshooting)

---

## 一、系統與建置需求規格

在編譯本專案前，請確認滿足以下元件版本要求：

| 項目 | 規格需求 | 備註說明 |
| :--- | :--- | :--- |
| **作業系統** | Ubuntu 22.04+ / macOS / Windows 10+ | 本手冊 CLI 範例以 Ubuntu 為主 |
| **Java JDK** | **OpenJDK 17** 或更高 (Java 17 / 21) | 專案指定 `JavaVersion.VERSION_17` |
| **Android Compile SDK** | **API 37** (Android 17) | 於 `app/build.gradle.kts` 中設定 |
| **Android Minimum SDK** | **API 28** (Android 9 Pie) | 支援 Android 9 及以上裝置 |
| **Gradle 版本** | **Gradle 9.6.1** | 由專案自帶的 `gradlew` 自動下載 |
| **Android Gradle Plugin** | **AGP 9.4.1** |  |
| **手機系統要求** | Android 9.0 或更高版本 | 需具備相機與麥克風功能 |

---

## 二、方法一：使用 Android Studio 建置（推薦）

這是最簡單直覺的方式，Android Studio 會自動處理 JDK、SDK 與相依套件的管理：

1. **安裝 Android Studio**：
   - 官方網站：[developer.android.com/studio](https://developer.android.com/studio)
   - 或在 Ubuntu 使用 Snap 快速安裝：
     ```bash
     sudo snap install android-studio --classic
     ```
2. **開啟專案**：
   - 啟動 Android Studio，在歡迎畫面點擊 **Open**。
   - 選取本專案根目錄 (`CamMonitor`)。
3. **自動同步與安裝 SDK**：
   - Android Studio 會讀取 `build.gradle.kts` 並自動進行 Gradle Sync。
   - 若本地缺少 **Android SDK Platform 37** 或 **Build-Tools**，介面下方會出現安裝提示，點擊 **Install Build Tools and sync project** 即可自動下載。
4. **編譯並安裝至手機**：
   - 將 Android 手機開啟「USB 偵錯」並連接電腦。
   - 點擊工具列右上角的綠色播放按鈕 **Run 'app'** (`Shift + F10`)，即會自動編譯並安裝至手機。

---

## 三、方法二：Linux 純終端機命令列 (CLI) 建置

適用於無圖形介面的伺服器、Docker 容器或 CI/CD 自動化建置流程。

### 1. 安裝系統相依套件與 OpenJDK 17

開啟終端機執行：

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk git wget unzip adb
```

驗證 Java 版本（需確認為 17 以上）：
```bash
java -version
```

---

### 2. 下載與安裝 Android SDK 命令列工具

建立存放 SDK 的目錄並下載官方 `commandlinetools`：

```bash
# 建立目錄
mkdir -p ~/Android/Sdk/cmdline-tools

# 下載命令列工具套件
cd /tmp
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip

# 解壓縮並依規範擺放至 latest 目錄
unzip -q commandlinetools-linux-11076708_latest.zip -d ~/Android/Sdk/cmdline-tools
mv ~/Android/Sdk/cmdline-tools/cmdline-tools ~/Android/Sdk/cmdline-tools/latest
rm /tmp/commandlinetools-linux-11076708_latest.zip
```

---

### 3. 設定環境變數

將 Java 與 Android SDK 路徑加入至使用者環境變數。編輯 `~/.bashrc`：

```bash
cat << 'EOF' >> ~/.bashrc

# Android & Java Build Environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
EOF
```

讓環境變數立即生效：
```bash
source ~/.bashrc
```

---

### 4. 下載 Android 平台與建置元件 (API 37)

透過 `sdkmanager` 接受授權條款，並安裝專案編譯所必需的 SDK 元件：

```bash
# 1. 自動接受所有授權合約
yes | sdkmanager --licenses

# 2. 下載編譯平台 (API 37)、Build-Tools 與 Platform-Tools
sdkmanager "platforms;android-37" "build-tools;35.0.0" "platform-tools"
```

---

## 四、專案編譯流程

進入本專案根目錄：

```bash
cd /home/sshsiung/projects/2026.10.19-CamMonitorFork/CamMonitor
```

### 1. 賦予 Gradle 執行權限
```bash
chmod +x gradlew
```

### 2. 執行單元測試 (Unit Tests)
可先執行專案單元測試以確認核心邏輯（加解密、防重放、信令協議）正常：
```bash
./gradlew testDebugUnitTest
```

### 3. 編譯 Debug 版 APK
執行建置指令：
```bash
./gradlew assembleDebug
```
編譯成功後，產出的 APK 檔案位於：
```text
app/build/outputs/apk/debug/Camonitor-v1.0.3-YYYYMMDD_HHMMSS-debug.apk
```

---

### 4. 編譯 Release 正式簽署版 APK（可選）

若需要建置已簽署的正式版本：
1. 參考 `keystore.properties.example`，在專案根目錄建立 `keystore.properties`：
   ```properties
   storeFile=keystore/release.keystore
   storePassword=your_store_password
   keyAlias=your_key_alias
   keyPassword=your_key_password
   ```
2. 執行 Release 編譯指令：
   ```bash
   ./gradlew assembleRelease
   ```
   產出路徑為 `app/build/outputs/apk/release/Camonitor-v1.0.3-*.apk`。

---

## 五、安裝至 Android 手機

### 1. 開啟手機端 USB 偵錯
1. 進入手機 **設定 (Settings)** $\to$ **關於手機 (About Phone)**。
2. 連續點擊 **版本號碼 (Build Number)** 7 次，解鎖「開發人員選項」。
3. 返回設定，進入 **系統 (System)** $\to$ **開發人員選項 (Developer Options)**。
4. 開啟 **USB 偵錯 (USB Debugging)**。

---

### 2. 驗證連線並安裝 APK

將手機透過傳輸線連接電腦：

1. **確認裝置已連線**：
   ```bash
   adb devices
   ```
   *手機螢幕若跳出「允許 USB 偵錯？」提示，請勾選「一律允許」並點擊確定。終端機狀態應顯示為 `device`。*

2. **方法 A：透過 Gradle 一鍵安裝**
   ```bash
   ./gradlew installDebug
   ```

3. **方法 B：透過 ADB 直接安裝編譯好的 APK**
   ```bash
   adb install -r app/build/outputs/apk/debug/*.apk
   ```

---

## 六、常見問題與故障排除 (Troubleshooting)

### Q1: 出現 `ERROR: JAVA_HOME is not set`
- **原因**：系統找不到 JDK 安裝路徑。
- **解法**：確認已安裝 `openjdk-17-jdk`，並執行：
  ```bash
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  ```

### Q2: 出現 `./gradlew: Permission denied`
- **原因**：`gradlew` 腳本缺少執行權限。
- **解法**：
  ```bash
  chmod +x gradlew
  ```

### Q3: 出現 `SDK location not found`
- **原因**：Gradle 找不到 Android SDK 路徑。
- **解法**：確認已設定 `ANDROID_HOME`，或在專案根目錄建立 `local.properties` 檔案：
  ```properties
  sdk.dir=/home/<使用者名稱>/Android/Sdk
  ```

### Q4: 出現 `Failed to install the following Android SDK packages as some licences have not been accepted`
- **原因**：尚未同意 Android SDK 授權。
- **解法**：執行以下指令同意所有條款：
  ```bash
  yes | sdkmanager --licenses
  ```

### Q5: 手機安裝後畫面全黑或相機無法開啟
- **原因**：未授予權限或相機被其他應用程式占用。
- **解法**：
  1. 請於手機「應用程式設定」內檢查並授予 **相機**、**麥克風** 與 **通知** 權限。
  2. 若鏡頭端 60 秒無人觀看會進入「自動待命省電模式」，點擊畫面「啟動相機」即可手動喚醒。
