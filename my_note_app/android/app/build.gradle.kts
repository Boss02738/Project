plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // แทน kotlin-android แบบเก่า
    // Flutter plugin ต้องตามหลัง Android+Kotlin เสมอ
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_note_app"

    // ใช้ค่าจาก Flutter สำหรับ sdk
    compileSdk = flutter.compileSdkVersion

    // ✅ ตั้ง NDK 27 ให้ชัด (อย่าเซ็ตซ้ำจาก flutter.ndkVersion)
    ndkVersion = "27.0.12077973"

    // ✅ ใช้ Java 17 ให้ตรงกับ AGP/ปลั๊กอินใหม่ ๆ
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.my_note_app"
        minSdk = flutter.minSdkVersion
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
