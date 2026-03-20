# TestFlight Setup Guide for Codemagic

This guide will help you set up automated iOS builds and TestFlight deployment using Codemagic from your NixOS machine.

## Prerequisites

- Apple Developer Account ($99/year)
- GitHub account
- Codemagic account (free tier works for getting started)

## Step 1: Apple Developer Setup

### 1.1 Create App in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Click "My Apps" → "+" → "New App"
3. Fill in:
   - **Platform:** iOS
   - **Name:** Trans (or your app name)
   - **Primary Language:** English
   - **Bundle ID:** `de.khonager.trans.ios`
   - **SKU:** Can be same as bundle ID
4. Click "Create"

**Note:** You don't need to fill in screenshots, descriptions, etc. Just creating the app record is enough for TestFlight.

### 1.2 Generate App Store Connect API Key

This allows Codemagic to upload builds automatically:

1. In App Store Connect, go to **Users and Access**
2. Click **Keys** tab → **App Store Connect API**
3. Click "+" to generate a new key
4. Give it a name (e.g., "Codemagic")
5. Select **Developer** or **App Manager** role
6. Click **Generate**
7. **Important:** Download the `.p8` file immediately (you can only download once!)
8. Note these three values:
   - **Key ID** (shows in the table)
   - **Issuer ID** (shows at the top of the page)
   - **Private Key** (contents of the .p8 file)

### 1.3 Get Your App ID

1. In App Store Connect, go to "My Apps"
2. Click on your app
3. Look at the URL: `https://appstoreconnect.apple.com/apps/YOUR_APP_ID/appstore`
4. Note the numeric **APP_ID** (e.g., 1234567890)

## Step 2: Codemagic Setup

### 2.1 Create Codemagic Account

1. Go to [codemagic.io](https://codemagic.io)
2. Sign up with your GitHub account
3. Authorize Codemagic to access your repository

### 2.2 Add Your Repository

1. In Codemagic dashboard, click "Add application"
2. Select your Trans repository
3. Choose "Flutter App"
4. Codemagic will detect the `codemagic.yaml` file

### 2.3 Configure Code Signing

**Option A: Automatic (Recommended - Easiest)**

1. In Codemagic, go to your app → **Settings** → **Code signing**
2. Click **iOS code signing**
3. Select **Automatic code signing**
4. Connect your Apple Developer account
5. Codemagic will automatically create and manage certificates/profiles

**Option B: Manual**

If you have certificates from the borrowed Mac:

1. Export certificates from Mac's Keychain Access as `.p12` files
2. In Codemagic, upload:
   - Distribution certificate (.p12)
   - Distribution provisioning profile (.mobileprovision)

### 2.4 Add Environment Variables

1. In Codemagic, go to **Settings** → **Environment variables**
2. Create a new group called `app_store_credentials`
3. Add these variables:

| Variable Name | Value | Secure? |
|---------------|-------|---------|
| `APP_STORE_CONNECT_PRIVATE_KEY` | Contents of your .p8 file | ✅ Yes |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Your Key ID | ✅ Yes |
| `APP_STORE_CONNECT_ISSUER_ID` | Your Issuer ID | ✅ Yes |
| `SUPABASE_URL` | Your Supabase project URL | ✅ Yes |
| `SUPABASE_ANON_KEY` | Your Supabase anon key | ✅ Yes |

4. Also update the `codemagic.yaml` file with your App Store App ID:
   - Edit line with `APP_STORE_APP_ID: "YOUR_APP_ID"`
   - Replace with your numeric app ID

### 2.5 Update Email Notification

In `codemagic.yaml`, update:
```yaml
email:
  recipients:
    - your-email@example.com  # Change this!
```

## Step 3: Build and Deploy

### 3.1 Trigger a Build

**Method 1: Manual (from NixOS)**
1. Go to Codemagic dashboard
2. Select your app
3. Select workflow: `ios-testflight`
4. Click "Start new build"

**Method 2: Automatic (on push)**
- Push to your `stable` branch
- Codemagic will automatically start a build

### 3.2 Monitor Build

1. Watch the build logs in real-time in Codemagic dashboard
2. The build takes about 15-30 minutes
3. If successful, the IPA will be automatically uploaded to TestFlight

## Step 4: TestFlight

### 4.1 Wait for Processing

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Go to your app → **TestFlight** tab
3. Your build will appear in "Processing" status (takes 5-15 minutes)
4. Once processed, it moves to "Ready to Test"

### 4.2 Add Internal Testers

1. In TestFlight tab, click **Internal Testing**
2. Click "+" to create a test group (e.g., "Internal Testers")
3. Add yourself and team members (up to 100)
4. They'll receive an email to install TestFlight app and your build

### 4.3 Add External Testers (Optional)

1. Click **External Testing** → "+" to create group
2. Add testers by email (up to 10,000)
3. First external build requires a quick automated review (~24 hours)
4. This is NOT the full App Store review - it's just automated checks

## Step 5: Install on Your iPhone

1. On your iPhone, install **TestFlight** app from App Store
2. Check your email for TestFlight invitation
3. Tap "View in TestFlight" button
4. Install your app!

## Troubleshooting

### "Missing code-signing certificate"
- Make sure you set up code signing in Codemagic (Step 2.3)
- Try automatic code signing first - it's easier

### "Invalid Provisioning Profile"
- Ensure you're using a **Distribution** profile, not Development
- Check that bundle ID matches exactly: `de.khonager.trans.ios`

### "App Store Connect API authentication failed"
- Double-check your .p8 file contents (including BEGIN/END lines)
- Verify Key ID and Issuer ID are correct
- Make sure the API key has Developer or App Manager role

### Build fails during "pod install"
- Usually transient - just retry the build
- Check if any iOS dependencies have issues

### Can't see build in TestFlight
- Wait 5-15 minutes for processing
- Check for email from Apple about any issues
- Look in "Activity" tab in App Store Connect for errors

## Tips

1. **First Build Takes Time:** Your first successful build might take a few tries to get code signing right. Be patient!

2. **Development Builds:** Use the `ios-development` workflow for testing builds without uploading to TestFlight

3. **Logs:** Always check the Codemagic build logs if something fails - they're very detailed

4. **Cost:** Codemagic free tier includes 500 build minutes/month. TestFlight builds use about 20-30 minutes each.

5. **Automatic Builds:** Once set up, every push to `stable` branch will trigger a TestFlight build automatically!

## Next Steps

After your first successful TestFlight build:

1. Share TestFlight link with testers
2. Gather feedback
3. Iterate on your app
4. When ready, submit for App Store review through App Store Connect

---

**Need Help?**
- Codemagic Docs: https://docs.codemagic.io/flutter/ios-code-signing/
- TestFlight Guide: https://developer.apple.com/testflight/
