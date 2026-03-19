# UniDrop

UniDrop 是一個 Flutter 區域網路傳輸應用程式，提供裝置間的檔案與文字傳送、QR 配對、媒體編輯與基本安全保護。

## ✨ 功能

- 區域網路裝置探索（UDP Multicast）。
- 透過本機 HTTP 服務進行檔案與文字傳輸。
- QR code 分享連線資訊與掃描配對。
- 傳送前圖片編輯（Image Editor）。
- 傳送前影片裁切與封面編輯（Android / iOS）。
- 最愛裝置與多裝置選取傳送。
- 設定頁提供裝置別名、主題、儲存目錄等設定。
- 可選生物辨識解鎖（依平台支援）。
- 使用加密偏好儲存（Encrypted Shared Preferences）。

## 🧱 技術重點

- Flutter + Riverpod 狀態管理。
- 傳輸協定：HTTP（檔案 multipart + 文字 plain text）。
- 探索機制：UDP Multicast（預設 224.0.0.1:2706）。
- 主要模組位於 `lib/features/`（discovery、send、server、receive、security）。

## 🚀 快速開始

### 環境需求

- Flutter SDK（`pubspec.yaml` 目前為 `>=3.0.0 <4.0.0`）。
- 對應平台建置工具（Android Studio / Xcode / Visual Studio 等）。

### 安裝

```bash
git clone <repository-url>
cd unidrop
flutter pub get
```

### 執行

```bash
flutter run
```

## 📱 使用流程

1. 在同一區域網路啟動兩台以上裝置上的 UniDrop。
2. 等待裝置自動出現在清單，或用 QR code 掃描配對。
3. 選擇要傳送的檔案（圖片 / 影片 / 一般檔案）或輸入文字。
4. 可選擇先編輯圖片或影片，再送出到目標裝置。
5. 接收端可預覽並儲存收到的檔案或文字。

## 🔐 權限與平台注意事項

- Android 需宣告媒體存取權限（如 `READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`）。
- iOS 需提供 `NSPhotoLibraryUsageDescription` 與 `NSPhotoLibraryAddUsageDescription`。
- 生物辨識在 Android 需宣告 `USE_BIOMETRIC` / `USE_FINGERPRINT`。

## 🧪 測試

```bash
flutter test
```
