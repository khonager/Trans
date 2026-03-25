# Trans – Public Transit Companion


[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-blue?logo=flutter)](https://flutter.dev)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web%20%7C%20Desktop-lightgrey)]()

A cross-platform public transit app built with **Flutter**. Plan routes, track your journey with wake-up alarms, share your location with friends, and never miss your stop again.

---

## 📲 Install via Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) allows you to install and update apps directly from GitHub releases.

### Quick Install (Recommended)
Click the button below to automatically add the app to Obtainium:

[![Add to Obtainium](https://img.shields.io/badge/Add%20to-Obtainium-blue?logo=android)](https://apps.obtainium.imranr.dev/redirect?app=%7B%22id%22%3A%22io.github.khonager.trans%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fkhonager%2FTrans%22%2C%22author%22%3A%22khonager%22%2C%22name%22%3A%22Trans%22%2C%22preferredApkIndex%22%3A0%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22filterReleaseNotesByRegEx%5C%22%3A%5C%22%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22dontSortReleasesList%5C%22%3Afalse%7D%22%7D)

### Manual Setup

1. **Install Obtainium** from [GitHub](https://github.com/ImranR98/Obtainium/releases) or [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/)

2. **Open Obtainium** and tap **+** to add a new app

3. **Paste the repository URL:**
   ```
   https://github.com/khonager/Trans
   ```

4. Tap **Add** – Obtainium will download the latest APK

> **Note:** Enable "Unknown sources" for Obtainium in Android settings.

---

## 🛒 Install via F-Droid Repo

You can also install and update Trans from the custom F-Droid repository:

`https://khonager.github.io/f-droid/repo`

### Manual Setup

1. **Install an F-Droid client** (F-Droid, Neo Store, or Droid-ify)
2. **Open your client** and add a new repository
3. **Paste this repo URL:**
   ```
   https://khonager.github.io/f-droid/repo
   ```
4. **Refresh repositories**, then install:
   - **Trans** (stable)
   - **Trans Dev** (separate dev app)

---

## 🧪 Bleeding Edge / Dev Builds

For those who want the absolute latest features (and bugs!), you can install the **Dev Build**. This version is updated automatically with every change to the source code.

> [!CAUTION]
> **Expect Bugs!** Dev builds may crash or have broken features. We recommend keeping the stable version installed as a backup.

### Install Dev Build via Obtainium

1. In Obtainium, **Add App** -> **Paste URL**: `https://github.com/khonager/Trans`
2. Scroll down to **"Additional Settings"**
3. Enable **"Include Prereleases"**
4. Set **"Filter Release Titles by Regular Expression"** to `Latest Dev Build`
5. Tap **Add**

---

## ✨ Features

### 🚆 Route Planning
Search for routes between any two stations or addresses. The app uses your **current GPS location** as the default starting point when the "From" field is empty.

- **Multi-modal routing** – Supports trains, buses, trams, subways, and walking segments
- **Alternative routes** – Tap on any connection to see earlier/later alternatives
- **Live departures** – Real-time departure times with delay information
- **Address support** – Navigate to/from street addresses, not just stations

### ⏰ Wake-Up Alarm
Never miss your stop! Activate a wake-up alarm for any journey to get notified before you arrive.

- **Configurable trigger** – Set the alarm to go off 0-3 stops before your destination
- **Customizable vibration patterns** – Choose from 15 different patterns including movie themes
- **Adjustable intensity** – Fine-tune vibration strength (1-255)
- **Visual + haptic alerts** – Combines notifications with vibration

### ⭐ Favorites
Save frequently used locations for one-tap route planning.

- **Custom icons** – Choose from 13 different icons (home, work, gym, etc.)
- **Custom names** – Label your favorites however you like
- **Quick routing** – Tap a favorite to instantly plan a route there

### 👥 Friends & Location Sharing
Connect with friends and share your real-time location.

- **Add friends** – Search by username and send friend requests
- **Live location** – See where your friends are on a map
- **Navigate to friends** – Plan routes directly to a friend's current location
- **Private chat** – Message friends directly within the app
- **Ghost Mode** – Hide your location from everyone with one toggle

### 🌐 Multiple Data Sources
The app supports multiple transit APIs for broad coverage:

- **Transitous (MOTIS)** – Open-source, pan-European coverage
- **Deutsche Bahn (v6)** – Legacy DB API as fallback
- **Auto mode** – Automatically chooses the best source

---

## ⚙️ Settings Reference

### Privacy
| Setting | Description |
|---------|-------------|
| **Ghost Mode** | When enabled, your location is hidden from all friends. The toggle turns red when active. |

### Display
| Setting | Description |
|---------|-------------|
| **Dark Mode** | Toggle between light and dark themes. Long-press to enable/disable system sync. |
| **Theme Color** | Choose your accent color from a palette of options. Applied throughout the app. |

### Transport Options
| Setting | Description |
|---------|-------------|
| **Deutschlandticket Mode** | When enabled, only shows local/regional transport (no ICE, IC, EC). Perfect for Deutschlandticket holders. |

### Notifications & Haptics
| Setting | Description |
|---------|-------------|
| **Alarm Trigger** | Choose when to be alerted: at destination, or 1/2/3 stops before. |
| **Alarm Pattern** | Select a vibration pattern. Options include: Standard, Heartbeat, Tick, Mario, 20th Century Fox, Imperial March, Harry Potter, Indiana Jones, Mission Impossible, Terminator, Back to the Future, Evangelion, Pokémon, Attack on Titan, Cowboy Bebop. |
| **Vibration Intensity** | Slider from 1-255 to control how strong the vibration is (on supported devices). |

### Data & Privacy
| Setting | Description |
|---------|-------------|
| **Blocked Users** | View and manage your blocked users list. Blocked users cannot see your location or send messages. |
| **Clear Search History** | Delete your recent search history from the device. |

### Advanced
| Setting | Description |
|---------|-------------|
| **Transport API** | Choose the data source: **Auto** (recommended), **Transitous** (open-source MOTIS), or **DB v6** (legacy Deutsche Bahn). |

### Profile (when logged in)
- **Avatar** – Tap to choose an emoji as your profile picture
- **Username** – Edit your display name
- **Email** – Update your email address
- **Password** – Change your password
- **Log Out** – Sign out of your account

---

## 🚀 Getting Started (Development)

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.10.0+)
- Xcode (iOS/macOS)
- Android Studio (Android)

### Installation

```bash
# Clone the repository
git clone https://github.com/khonager/Trans.git
cd Trans

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Using Nix (Recommended)

If you have [Nix](https://nixos.org/) installed, you can use the included `flake.nix` to get a complete development environment with all dependencies:

```bash
# Enter the development shell
nix develop

# Then run as usual
flutter pub get
flutter run
```

This automatically provides Flutter, Dart, Android SDK, and all other required tools without manual installation.

---

## 🏗 Building

### Mobile
```bash
# Android APK
flutter build apk

# Android App Bundle (Play Store)
flutter build appbundle

# iOS (requires Xcode signing)
flutter build ios
```

### Desktop & Web
```bash
# macOS
flutter build macos --release

# Windows
flutter build windows --release

# Web
flutter build web --release --web-renderer canvaskit
```

---

## 🛠 Maintenance

```bash
# Check for issues
flutter analyze

# Format code
dart format .

# Clean build artifacts
flutter clean && flutter pub get
```

---

## 🍴 Forking

This project does not accept contributions, but you're welcome to fork it and make it your own!


---

## 📄 License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)**.

### Summary
- ✅ **Share**: You are free to copy and redistribute the material.
- ✅ **Adapt**: You are free to remix, transform, and build upon the material.
- ❌ **NonCommercial**: You may **NOT** use the material for commercial purposes (selling the app).
- 🔄 **ShareAlike**: If you remix, transform, or build upon the material, you must distribute your contributions under the same license.

See the `LICENSE` file for the full legal text.
