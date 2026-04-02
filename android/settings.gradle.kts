pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
            properties.getProperty("flutter.sdk")
        } else {
            System.getenv("FLUTTER_ROOT")
        }
    }

    if (flutterSdkPath != null) {
        includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // ✅ محرك تحميل إضافات فلاتر
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // ✅ إصدار Gradle Plugin المتوافق مع أندرويد 14 و15
    id("com.android.application") version "8.9.1" apply false

    // ✅ إعدادات خدمات جوجل وكراشليتكس (إصدارات مستقرة لأكسب)
    id("com.google.gms.google-services") version "4.4.1" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false

    // 🚀 التعديل الجوهري: تحديث الكوتلن لحل تعارض الـ Metadata والـ Daemon
    id("org.jetbrains.kotlin.android") version "2.3.10" apply false
}

include(":app")

