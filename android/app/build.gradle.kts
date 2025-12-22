plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.trans"
    
    // FIX: MUST BE 34. DO NOT CHANGE TO 36.
    compileSdk = 34
    
    // FIX: Match the NDK version in your flake.nix
    ndkVersion = "26.1.10909125"
    // Explicitly set the path if needed, but ndkVersion is usually enough with the env var
    val ndkRoot = System.getenv("ANDROID_NDK_ROOT")
    if (ndkRoot != null) {
        ndkPath = ndkRoot
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.trans"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}