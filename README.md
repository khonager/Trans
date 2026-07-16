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
   - **Trans Dev** (dev channel build)

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

### 👥 Friends & Journey Signal
Connect with friends and automatically share as much—or as little—of a detected journey as you choose.

- **Add friends** – Search by username and send friend requests
- **Signal levels 0–8** – Progress from Ghost through line, times, destination, itinerary, journey progress, exact location, routing, and favorites
- **Per-friend overrides** – Use a global default while granting a different level to individual friends
- **Automatic journey detection** – Open route candidates are matched using time and low-power location signals; searches alone are never published
- **Navigate to friends** – At level 7+, use a friend's latest location in From/To search
- **Shared favorites** – At level 8, use a friend's synced favorite places in route search
- **Private chat** – Message friends directly within the app
- **Level 0 / Ghost** – Stop sharing and clear published presence

### 🌐 Multiple Data Sources
The app supports multiple transit APIs for broad coverage:

- **Transitous (MOTIS)** – Open-source, pan-European coverage
- **Deutsche Bahn (v6)** – Legacy DB API as fallback
- **Auto mode** – Automatically chooses the best source

---

## Data Storage & Privacy

Trans should be understandable about user data. The app does not hide what it saves: some data is stored only on the device, some is copied to your Trans account so it can appear on all signed-in devices, and some social features are stored in Supabase so friends, chat, tickets, and account features can work.

If you are not signed in, account-cloud sync is skipped, but route planning and transit lookups still contact the selected transport APIs.

### Saved only on this device

These values stay local to the current app install/device and are not intentionally synced to your Trans account:

| Data | Why it is saved |
|------|-----------------|
| Current tab index | Opens the app on the last selected tab. |
| Show train numbers toggle | Remembers local display preference. |
| Always wake me toggle | Remembers local wake-alarm behavior. |
| Enabled transport API sources | Remembers whether this device uses Transitous, synthetic Transitous, DB v6, or a combination. |
| Advanced settings unlocked flag | Keeps the advanced settings UI unlocked on this device only. |
| Per-device bike toggle for advanced routing | Remembers the quick bike-routing toggle on this device. |
| Community terms accepted flag | Avoids asking again on the same device. |
| Custom alarm sound files | Imported audio is copied into the app's local support folder. The sound file itself is not uploaded. |
| Custom alarm sound metadata | Stores local file path, file name, label, and custom sound id so the local file can be used. |
| Local ticket copy | Native apps save ticket JPG files in the app documents folder; web saves the ticket image as base64 in browser/app preferences. |
| Notification/alarm runtime state | Active timers, GPS stream state, and notification channel setup are local runtime/device behavior. |
| Supabase sign-in session | The Supabase SDK keeps a local auth session so you stay signed in. |

Clearing app data or uninstalling the app removes local-only data from that device.

### Saved locally and synced to your account

The app stores these locally first and also writes them to your Supabase profile when you are signed in. On another signed-in device, Trans downloads them and writes a local copy there too.

| Data | What it can contain |
|------|---------------------|
| Recent station/address searches | Station or address id, name, type, coordinates when available, city/region/country/postal code metadata. Kept to a maximum of 10 recent entries. |
| Frequent journeys | From/to station or address data, timestamp, and usage count. Kept to a maximum of 30 entries. |
| Recent route searches | From/to station or address data and timestamp. Kept to a maximum of 30 entries. |
| Saved journeys | From/to data, departure and arrival times, expiry time, connection key, selected journey details, and leave reminder settings. Saved journeys expire after arrival plus 24 hours. |
| Favorites | Favorite label, icon, station/address data, and type. Friend favorites are intentionally filtered out; synced favorites are station/address favorites only. |
| Theme and display settings | Dark mode, system theme sync, accent color, claimed color metadata, and language. |
| Transit preferences | Deutschlandticket/local transport mode and advanced routing values such as transfer time, walk/bike options, walking speed, cycling speed, and maximum walking time. |
| Alarm and haptic settings | Vibration pattern, intensity, selected wake-alarm sound id, sound/vibration toggles, and alarm stop count. The alarm trigger threshold is uploaded to account settings when changed, but the current settings download path does not restore it on other devices yet. |
| Journey Signal setting | Global sharing level from 0–8. Level 0 is Ghost. Existing per-friend overrides are stored in the cloud. |

One important custom sound detail: the selected sound id can sync, but the imported audio file does not. A custom sound chosen on one device may not exist on another device unless it is imported there too.

### Saved in the cloud for account, friends, and sharing

These are stored in Supabase because they are account or social features:

| Data | How it is used |
|------|----------------|
| Account identity | Email address, Supabase user id, auth provider data, username, password/auth credentials managed by Supabase Auth, and password reset/email confirmation state. |
| Profile and sharing settings | Username, avatar fields, theme color, global Journey Signal level, per-friend overrides, settings JSON, favorites JSON, ticket URL, and timestamps. |
| Detected journey presence | A generated journey id, active state, transit line, planned start/end, destination station, transit-only itinerary, journey-relative progress, expiry, and update time. Walking addresses are excluded from the shared itinerary. |
| Location snapshot | Latest latitude, longitude, accuracy, and update time when an effective friend level requires it. The snapshot is replaced rather than accumulated into a location history. Level 6 exposes it only during a detected journey; levels 7–8 keep it available for friend routing. |
| Signal level enforcement | A database function calculates each friend's effective override-or-global level and removes fields above that level before returning presence. Level 0 deletes published presence. |
| Friends | Friend relationships and friend request sender/receiver/status rows. |
| Blocked users | Blocker id and blocked user id. Blocking also removes the friendship link. |
| Messages | Public line chat messages are stored as plaintext. Private messages are encrypted by the app before upload and stored with sender/receiver ids, but the key is derived from the two account ids, so do not treat it as high-security end-to-end encryption. |
| Ticket upload | Ticket images are uploaded to the Supabase `tickets` storage bucket and the resulting public URL is stored on your profile. Anyone with that URL may be able to view the image. |
| Theme color claims | Claimed color hex value, app id, owner/user ids, owner label, linked portfolio uid when present, timestamps, and sync status. |
| Portfolio sign-in/color sync | If used, the app opens the portfolio sign-in/sync flow and exchanges bridge/color-claim data with the configured portfolio endpoints. |

Deleting your account from the app calls the backend delete function, which removes your Supabase auth user plus app-owned profile, messages, friend requests, friend links, blocks, and live-location rows. Color claims are tied to the auth user and should be removed by database cascade. Uploaded ticket storage objects are not explicitly deleted by the current delete function, so contact support if a ticket upload also needs to be removed. Local data on a device may remain until you clear app data or uninstall the app.

### Sent to transport and platform services

Route planning, station search, nearby stops, live departures, and trip details are requested from the selected transport APIs:

- **Transitous** at `https://api.transitous.org`
- **DB v6** at `https://v6.db.transport.rest`

Those requests can include search text, station ids, coordinates, dates/times, routing preferences, and a Trans app user-agent string. The app keeps short-lived in-memory caches for some transport responses to avoid duplicate requests during the same session.

Device location is requested from the operating system when needed for current-location route planning, wake alarms, nearby transit features, automatic journey detection, and Signal levels that include location. Detection monitoring is limited to seven minutes around candidate departure and an active journey, uses movement filters, and reuses the wake-alarm or level-7 stream when one already exists. Levels 7–8 use a low-accuracy, distance-filtered background stream and may show a persistent operating-system indicator. Notification permissions are requested for alarms, route reminders, private messages, friend requests, and foreground location services where required.

Ticket image cropping, QR detection, and custom alarm sound import happen locally before anything is uploaded. The app does not include a dedicated analytics or crash-reporting SDK.

### Reports and support

When you report content, the app prepares an email to the support address. The report can include your user id, email, the reported user/content ids, reason, optional details, message preview, and, if you choose it, message history. That information is handled by your email app and email provider. If no mail app is available, the report text is copied to your clipboard.

---

## ⚙️ Settings Reference

### Privacy
| Setting | Description |
|---------|-------------|
| **Journey Signal** | Select a global level from 0–8. Level 0 shares nothing. Higher levels cumulatively share line, times, destination, itinerary, progress, journey location, always-available location, and favorites. |
| **Friend Signal override** | On an expanded friend card, use the global level or select a level that applies only to that friend. |

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
