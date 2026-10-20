# Local TV Ver. 2 🎬🍿

A modern, high-performance Windows desktop application built with **Flutter Desktop** and powered by the **LibMPV native engine (`media_kit`)**. 

Local TV Ver. 2 delivers a sleek, Netflix-inspired media center experience designed to browse and play your local movie and TV series collection seamlessly—**with zero popup windows or external player tabs**.

---

## ✨ Features

- **🚀 Embedded LibMPV Engine (`libmpv-2.dll`)**:
  - Full hardware acceleration (GPU decoding via DirectX / ANGLE / Vulkan).
  - Video plays directly inside the application canvas (*zero-copy GPU texture sharing*).
  - No external windows or taskbar popups when launching media.

- **🎨 Netflix-Inspired User Interface**:
  - Premium dark theme (`#111111`) with curated glassmorphism and Netflix red accents (`#E50914`).
  - Interactive top navigation bar with search, category filtering, and direct file/folder picker.
  - Dynamic Hero Billboard with spotlight banner, details modal, and instant playback.
  - Categorized horizontal scrolling rows (*Trending*, *Series*, *Blockbusters*, *Indonesian Cinema*).
  - Responsive layout optimized for desktop displays (1080p, 2K, 4K).

- **📁 Smart Local Movie Folder Scanner**:
  - Connect any movie/series folder on your computer (e.g. `D:\Movies`, `E:\Series`).
  - Automatic recursive scanning for all major video containers: `.mp4`, `.mkv`, `.avi`, `.mov`, `.webm`, `.ts`, `.m4v`, `.flv`, `.wmv`.
  - Intelligent filename cleaner: removes scene tags (`1080p`, `BluRay`, `WEBRip`, `x264`, `x265`, etc.) into clean titles.
  - Configuration persistence (`library_config.json`) so your library is ready instantly every time you open the app.

- **💬 Full Native Subtitle Engine (LibASS)**:
  - Subtitles rendered directly by the native C **LibASS** engine.
  - Complete support for advanced ASS/SSA typesetting (anime karaoke, custom positioning, embedded fonts).
  - Crisp, custom styling for standard subtitles (`.srt`): Trebuchet MS typography, pure white text, dark border outline, and soft shadow offset.
  - Automatic language priority for Indonesian and English subtitles.

- **🎛️ Custom In-App Player Controls**:
  - Minimalist auto-hiding control overlay.
  - Timeline scrubber, Play/Pause, Replay 10s, Forward 10s.
  - Volume slider with mute toggle.
  - In-app full-screen toggle and smooth back/close button.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter Desktop (Windows)](https://flutter.dev/multi-platform/desktop) (Dart 3.x)
- **Media Engine**: [MediaKit](https://github.com/media-kit/media-kit) (LibMPV C/C++ backend)
- **Video Renderer**: Impeller / OpenGL ES via ANGLE (DirectX 11)
- **File System**: `file_picker` & native `dart:io` directory traversal
- **Typography**: Google Fonts (Outfit / Inter / Trebuchet MS)

---

## 📦 Getting Started

### Prerequisites
- Windows 10 / 11 (64-bit)
- [Flutter SDK](https://flutter.dev) (v3.13+ or later)
- Visual Studio Build Tools 2022 (with *Desktop development with C++*)
- Windows Developer Mode enabled (for plugin symlink creation)

### Setup & Run
1. Clone the repository:
   ```bash
   git clone https://github.com/metalgarurumon99/Local-TV-Ver.-2.git
   cd "Local-TV-Ver.-2"
   ```

2. Fetch dependencies:
   ```bash
   flutter pub get
   ```

3. Run in debug mode:
   ```bash
   flutter run -d windows
   ```

4. Build release executable:
   ```bash
   flutter build windows
   ```
   The compiled standalone application will be located in:
   `build\windows\x64\runner\Release\local_tv.exe`

---

## 📄 License
This project is licensed under the MIT License.
