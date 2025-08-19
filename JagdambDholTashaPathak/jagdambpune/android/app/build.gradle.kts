plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jagdambpune.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion  = "28.2.13676358"

    signingConfigs {
        create("release") {
            keyAlias = "jagdamb-key"
            keyPassword = "Jagdamb@2025"
            storeFile = file("jagdamb.keystore") // Keystore file path relative to app folder
            storePassword = "Jagdamb@2025"
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false // Optional: enable if you want code shrinking
            isShrinkResources = false // Optional: enable if you want resource shrinking
        }
        getByName("debug") {
            // Use debug signing config for debug build
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.jagdambpune.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 2
        versionName = "1.0.1"
    }
}

flutter {
    source = "../.."
}
