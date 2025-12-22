# TRANS APP ⚡️

A next-generation transportation app built with Flutter. "Trans" fills the gaps left by current market leaders by integrating social features, smart routine monitoring, and granular journey details like seating suggestions and station guides.

---

## 🚀 FEATURES

### 1. Smart Alternatives 🔄
Don't just stick to the plan. The app actively lists available connections other than the current one from your transfer stop. 
* **Example:** If your Bus A is 5 minutes away, but Bus C (which also goes to your destination) is arriving now, the app suggests taking Bus C instead.

### 2. Seating Strategy 💺
Know where to sit before you board.
* **Function:** Suggests whether to sit in the **Back** (more space) or **Front** (quick exit) of the bus/train based on your next transfer or exit direction.

### 3. Tabbed Navigation 📑
Never lose your place.
* **Function:** Routes open as distinct tabs. You can have multiple active journeys running simultaneously and switch back and forth between them without losing your search state.

### 4. Social Commute (Friends) 📍
See your friends' live transit status.
* **Function:** Add friends and see exactly which bus or train line they are on (if they opt-in). It operates like a map-based social status for commuters.

### 5. Haptic Wake-Up 📳
Sleep safely on your commute.
* **Function:** The app vibrates your device when you need to get off at the next stop.

### 6. Routine Monitor 🔔
Set it and forget it.
* **Function:** Automatically detects routine transfers (e.g., Home ↔ Work). If a connection is delayed or cancelled, it notifies you immediately—even when you aren't using the app.

### 7. Station Guides 📸
Never get lost in a complex station.
* **Function:** Provides exact directions for difficult-to-find stations, including mock-ups of visual guides/pictures for specific platforms and exits.

### 8. Live Transit Chat 💬
Connect with your fellow commuters.
* **Function:** Automatically enters a chat room for the specific transportation vehicle you are in. Ask others if the bus is crowded or if the AC is working.

---

## 📖 TUTORIAL

### Getting Started
1.  **Launch the App:** Open the app to see the dashboard.
2.  **Location:** Allow location permissions to see nearby stops immediately.

### Planning a Journey
1.  Tap the **Search Icon** (or use the main input fields).
2.  Enter your **From** and **To** stations.
3.  Tap **Find Routes**.
4.  The route will open in a **New Tab** at the top of the screen.

### During the Trip
* **Check Alternatives:** In the route view, look for the "Alternatives" chip on specific steps to see other departures.
* **Wake Me Up:** Tap the **Vibration Icon** on a step to set a proximity alarm for that stop.
* **Chat:** Tap the **Chat Button** (e.g., "Chat (12)") to open the live room for that line.
* **Station Guide:** If available for your stop, tap **Guide** to see visual walking instructions.

---

## 💻 TERMINAL COMMANDS

### 1. Setup Dependencies
Install all required packages (http, geolocator, vibration, flutter_local_notifications):
```bash
flutter pub get
```

### 2. Run in Debug Mode
Start the app on your connected emulator or physical device:
```bash
flutter run
```

### 3. Build for Android (APK)
Generate a release APK for installation on Android devices:
```bash
flutter build apk
```

### 4. Analyze Code
Check for linting errors or style issues:
```bash
flutter analyze
```

### 5. Clean Build
If you encounter strange caching errors, run this to reset:
```bash
flutter clean
```
