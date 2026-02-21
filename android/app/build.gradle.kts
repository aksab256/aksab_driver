import java.util.Properties
import java.io.FileInputStream

// 1. إعداد قراءة ملف الخصائص المحلي
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // ✅ إضافة Plugin الكراشليتكس هنا
    id("com.google.firebase.crashlytics") 
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ⚠️ تأكد أن هذا الـ ID يطابق تماماً ما سجلته في Firebase Console
    namespace = "com.aksab.driver" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 2. إعدادات التوقيع الاحترافية
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

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        // ⚠️ يجب أن يطابق الـ Namespace فوق
        applicationId = "com.aksab.driver"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")

            // تفعيل الـ Minify و Shrink مهم جداً لتصغير حجم تطبيق المندوب
            isMinifyEnabled = true 
            isShrinkResources = true
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
