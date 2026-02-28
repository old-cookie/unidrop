# unidrop

A Flutter application enabling secure, local network file and text sharing between devices. Features include automatic device discovery, media editing capabilities, and an integrated AI chat assistant powered by a local Gemma model.

## ✨ Features

* **Local Network Discovery:** Automatically discover other devices running `unidrop` on the same network using `network_info_plus` and custom discovery logic (`lib/features/discovery/`).
* **Secure File & Text Transfer:** Share files (`file_picker`) and text messages (`clipboard`) directly between devices using a local HTTP server (`shelf`, `shelf_router`, `shelf_multipart`).
* **Image Editing:** Basic image editing functionalities provided by `image_editor_plus`.
* **Video Editing:** Basic video editing functionalities using `video_editor` and `ffmpeg_kit_flutter_new`.
* **AI Chat Assistant:** Chat with an onboard AI assistant using the Gemma model (`flutter_gemma`, `flutter_markdown`). The model runs locally (`assets/models/gemma3-1b-it-int4.task`).
* **Cross-Platform:** Built with Flutter, targeting Android, iOS, Web, Windows, macOS, and Linux.
* **Security:** Utilizes local authentication features (`local_auth`).

## 📸 Screenshots / Demo


## 🚀 Getting Started

### Prerequisites

* Flutter SDK installed (check `pubspec.yaml` for version constraints, currently `>=3.7.2 <4.0.0`)
* Platform-specific build tools (Android Studio/Xcode/Visual Studio/etc. depending on your target platform)

### Installation & Setup

1. **Clone the repository:**

    ```bash
    # Replace <repository-url> with the actual URL
    git clone <repository-url>
    cd unidrop
    ```

2.  **Install dependencies:**

    ```bash
    flutter pub get
    ```

### Running the App

1. Connect a device or start an emulator/simulator.
2. Run the app from your IDE or using the command line:

    ```bash
    flutter run
    ```

*(Note: Ensure necessary permissions (network, storage, camera, etc.) are granted, potentially handled by `permission_handler`.)*

## 💻 Usage

*(Placeholder: Briefly describe the user flow)*

1. Launch the app on two or more devices connected to the same local network.
2. Devices should automatically appear in the discovery list.
3. Select a device to initiate a connection or send data.
4. Use the interface to send files, text messages, or start an AI chat session.
5. Access image/video editing features through the relevant options (e.g., after selecting media).
