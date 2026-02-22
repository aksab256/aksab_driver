pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            // في GitHub Actions بنحتاج نتأكد إن الملف موجود أو نستخدم مسار افتراضي
            val localPropertiesFile = file("local.properties")
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
                properties.getProperty("flutter.sdk")
            } else {
                System.getenv("FLUTTER_ROOT") // غالباً ده المسار في GitHub Actions
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
    id("com.android.application") version "8.1.0" apply false // إصدار مستقر
    
    // ✅ تحديث خدمات جوجل لـ 4.4.1 (ده أهم تعديل)
    id("com.google.gms.google-services") version "4.4.1" apply false
    
    // ✅ إضافة الكراشليتكس هنا لتوحيد الإصدار
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
    
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")
