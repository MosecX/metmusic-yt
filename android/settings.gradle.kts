pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP is held at 8.x because flutter_inappwebview_android 1.1.3 is not yet
    // compatible with AGP 9: it calls getDefaultProguardFile("proguard-android.txt"),
    // which AGP 9 rejects at configuration time. Raise this once the plugin ships
    // an AGP 9 release, then drop the explicit Kotlin plugin in app/build.gradle.kts.
    id("com.android.application") version "8.12.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
