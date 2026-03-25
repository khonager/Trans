import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "de.khonager.trans"
    compileSdk = 36
    ndkVersion = "28.0.13004108"
    buildToolsVersion = "35.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // FIX 1: Enable Core Library Desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.khonager.trans"
        // You can update the following values to match your application needs.
        // For more information, see: https://docs.flutter.dev/deployment/android#reviewing-the-gradle-build-configuration.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    flavorDimensions += "version"
    productFlavors {
        create("stable") {
            dimension = "version"
            applicationId = "de.khonager.trans"
            manifestPlaceholders["appLabel"] = "Trans"
            manifestPlaceholders["clipboardAuthority"] = "de.khonager.trans.SuperClipboardDataProvider"
        }
        create("dev") {
            dimension = "version"
            applicationId = "de.khonager.trans"
            manifestPlaceholders["appLabel"] = "Trans Dev"
            manifestPlaceholders["clipboardAuthority"] = "de.khonager.trans.SuperClipboardDataProvider"
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isEmpty) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.create("release") {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                }
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            // Explicitly set to false to ensure 16KB alignment with AGP 8.3+ and NDK r28
            useLegacyPackaging = false
            // Exclude debug-only Vulkan validation layer (not 16KB aligned, not needed at runtime)
            excludes += "**/libVkLayer_khronos_validation.so"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // FIX 3: Workaround for ML Kit 16KB alignment issue in libimage_processing_util_jni.so
    implementation("androidx.camera:camera-core:1.4.2")
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}
