import java.util.Properties
import java.io.FileInputStream
// ✅ إضافة الـ Import ده هو السر لتعريف jvmTarget في النسخ الجديدة
import org.jetbrains.kotlin.gradle.dsl.JvmTarget 

// 1. إعداد قراءة ملف الخصائص المحلي
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// 1b. مفتاح خرائط Google: لا يُحفظ في Git أبداً. يُقرأ من
// android/local.properties (MAPS_API_KEY=...) أو من متغير البيئة
// MAPS_API_KEY (سِر CI). القيمة الفارغة تُبقي البناء أخضر؛ الخرائط
// تعمل بمجرد توفير مفتاح مقيد (package + SHA-1).
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}
val mapsApiKey: String =
    System.getenv("MAPS_API_KEY")?.takeIf { it.isNotBlank() }
        ?: localProperties.getProperty("MAPS_API_KEY", "")

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.aksab.driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            keyAlias = "upload"
            keyPassword = "1151983aA"
            storePassword = "1151983aA"

            val keystorePath = System.getenv("KEY_FILE_NAME") ?: "upload-keystore.jks"
            storeFile = file(keystorePath)
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    // ✅ الطريقة الرسمية والوحيدة المقبولة في Kotlin 2.3.10
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_1_8)
        }
    }

    defaultConfig {
        applicationId = "com.aksab.driver"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

