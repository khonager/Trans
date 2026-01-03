# Flutter Travel Companion

[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue?logo=flutter)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web%20%7C%20Desktop-lightgrey)]()

A comprehensive, cross-platform travel and transit application built with **Flutter**. Designed to streamline your daily commute and long-distance journeys, this app integrates digital ticketing, intelligent route planning, and social location features into a seamless user experience.

Whether you are commuting to work or exploring a new city, Travel Companion ensures you have your tickets, route, and friends just a tap away.

---

## 📲 Install via Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) allows you to install and update apps directly from their GitHub releases. Here's how to add this app:

### Quick Install (Recommended)
Click the button below to automatically add the app to Obtainium:

[![Add to Obtainium](https://img.shields.io/badge/Add%20to-Obtainium-blue?logo=android)](https://apps.obtainium.imranr.dev/redirect?app=%7B%22id%22%3A%22io.github.khonager.trans%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fkhonager%2FTrans%22%2C%22author%22%3A%22khonager%22%2C%22name%22%3A%22Trans%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Afalse%7D%22%7D)

### Manual Setup

1. **Install Obtainium** from [GitHub](https://github.com/ImranR98/Obtainium/releases) or [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/)

2. **Open Obtainium** and tap the **+** button to add a new app

3. **Paste the repository URL:**
   ```
   https://github.com/khonager/Trans
   ```

4. Tap **Add** and Obtainium will automatically detect and download the latest APK release

5. **Install** the app when prompted

> **Note:** Make sure "Unknown sources" is enabled for Obtainium in your Android settings to allow installation.

---

## ✨ Features

### 🎫 Digital Ticket Wallet
Never fumble for a paper ticket again. The **persistent bottom sheet** allows for a quick swipe-up gesture to access your active QR codes, NFC passes, or barcode tickets.
- **Offline Access:** Tickets are cached locally for access without internet.
- **Smart Sorting:** Active tickets appear first; expired tickets are archived automatically.

### ⭐ Dynamic Favorites
Save time by bookmarking your most frequented locations.
- **"Stations":** One-tap navigation to fixed locations like Home, Work, or your favorite gym.
- **"Friends":** Securely share locations with friends to navigate directly to their current live location (permission-based).

### ⏳ Time Travel Planning
A unique interface that allows you to "travel in time" to see transit conditions.
- **Future Planning:** Schedule trips for next week and see predicted traffic/transit delays.
- **Past Routes:** Review previous journeys to analyze travel time and cost.

### 📍 Smart Location Defaults
Streamlined input fields for faster booking.
- If the "From" field is left empty, the app intelligently defaults to your **current GPS location**.
- Adjusts automatically based on the context of your "Favorites" selection.

### 🛡️ Privacy Controls
Your location data belongs to you.
- **Ghost Mode:** completely hide your location from all friends.
- **Block List:** Specific controls to block individual users from seeing your live status.
- **Granular Permissions:** Choose to share "Precise" or "Approximate" location.

### 📳 Customizable Haptics & UI
- **Haptic Feedback:** Fine-tune the vibration strength for success, error, and warning states in `Settings > Haptics`.
- **Themes:** Supports System Light/Dark mode and custom high-contrast themes for accessibility.

### 🌍 Web Support (PWA)
Full Progressive Web App support means you can install this app on your desktop or mobile browser without an app store.

---

## 🚀 Getting Started

### Prerequisites
Ensure you have the following installed on your local machine:
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (Version 3.10.0 or higher recommended)
- [Dart SDK](https://dart.dev/get-dart)
- Xcode (for iOS/macOS development)
- Android Studio (for Android development)
- Visual Studio (for Windows desktop development)

### Installation

1. **Clone the repository**
   ```bash
   git clone [https://github.com/yourusername/flutter-travel-companion.git](https://github.com/yourusername/flutter-travel-companion.git)
   cd flutter-travel-companion
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Setup Environment Variables**
   Create a `.env` file in the root directory and add your API keys (e.g., Google Maps, Backend URL):
   ```env
   GOOGLE_MAPS_API_KEY=your_api_key_here
   API_BASE_URL=[https://api.example.com](https://api.example.com)
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

---

## 🏗 Building the App

To build the application for release on various platforms, use the specific build commands below.

### Desktop & Web
```bash
# macOS (creates a .app bundle)
flutter build macos --release

# Windows (creates an .exe)
flutter build windows --release

# Web (creates a generic HTML/JS build in /build/web)
flutter build web --release --web-renderer canvaskit
```

### Mobile
```bash
# Android (App Bundle for Play Store)
flutter build appbundle

# Android (APK)
flutter build apk

# iOS (Requires Xcode signing)
flutter build ios
```

---

## 🛠 Maintenance & Quality

### Code Formatting & Analysis
We enforce strict linting rules to ensure code quality.

**Analyze Code:**
Check for linting errors, type issues, or style violations before committing.
```bash
flutter analyze
```

**Format Code:**
Automatically format your Dart code to standard conventions.
```bash
dart format .
```

### Cleaning the Build
If you encounter strange caching errors, asset loading issues, or build artifacts, run this to reset the build environment.
```bash
flutter clean
flutter pub get
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:
1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.