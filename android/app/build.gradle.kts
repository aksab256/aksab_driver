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
    // تم نقل الـ Flutter Plugin ليكون قبل خدمات جوجل لضمان التوافق
    id("dev.flutter.flutter-gradle-plugin")
    
    // ✅ تحديث إصدار خدمات جوجل لحل مشكلة Crashlytics 3
    id("com.google.gms.google-services") version "4.4.1" apply true
    
    // ✅ تحديث إصدار الكراشليتكس ليتوافق مع خدمات جوجل
    id("com.google.firebase.crashlytics") version "3.0.2" apply true
}

android {
    // تم التأكيد على أن الـ Namespace يطابق Firebase و Google Play
    namespace = "com.aksab.driver" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 2. إعدادات التوقيع الاحترافية (Release Signing)
    signingConfigs {
        create("release") {
            keyAlias = "upload"
            keyPassword = "1151983aA"
            storePassword = "1151983aA"
            
            // يقرأ ملف التوقيع من البيئة أو يستخدم الملف المحلي
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
        // الـ Application ID النهائي لتطبيق المندوب
        applicationId = "com.aksab.driver"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")

            // تحسينات لتقليل حجم الـ AAB وحماية الكود
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
    // لدعم الميزات الحديثة على إصدارات أندرويد القديمة
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
