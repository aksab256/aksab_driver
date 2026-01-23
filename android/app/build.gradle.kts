plugins {
    id("com.android.application")
    id("kotlin-android")
    // تم إضافة السطر التالي لربط Firebase
    id("com.google.gms.google-services")
    // الـ Flutter Gradle Plugin يجب أن يكون الأخير
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.aksab_driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ تفعيل الـ Desugaring لحل مشكلة مكتبة الإشعارات
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        // الـ target المفضل للمكتبات هو 1.8 لضمان أوسع توافق
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.aksab_driver"
        // ✅ الـ Desugaring يتطلب minSdk لا يقل عن 21
        minSdk = 21 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// ✅ إضافة المكتبة المسؤولة عن الـ Desugaring في الخلفية
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
