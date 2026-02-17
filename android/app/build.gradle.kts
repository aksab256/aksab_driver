import java.util.Properties
import java.io.FileInputStream

// 1. إعداد قراءة ملف الخصائص المحلي (اختياري للتطوير المحلي)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.aksab_driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 2. إعدادات التوقيع الاحترافية
    signingConfigs {
        create("release") {
            // الأولوية لمتغيرات GitHub Secrets، ثم لملف key.properties المحلي
            keyAlias = "upload"
            keyPassword = "1151983aA"
            storePassword = "1151983aA"
            
            // تحديد مسار ملف الـ JKS الذي رأيناه في مجلد المشروع
            val keystorePath = System.getenv("KEY_FILE_NAME") ?: "upload-keystore.jks"
            storeFile = file(keystorePath)
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.aksab_driver"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // تفعيل التوقيع الرسمي للنسخة النهائية
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }

        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

