pluginManagement {
    val flutterSdkPath =
        run {
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
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // ✅ تم التحديث لـ 8.1.1 ليتوافق مع متطلبات فلاتر الحالية
    id("com.android.application") version "8.9.1" apply false 
    
    // ✅ حافظنا على 4.4.1 عشان مشكلة الكراشليتكس
    id("com.google.gms.google-services") version "4.4.1" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
    
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
