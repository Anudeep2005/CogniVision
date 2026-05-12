import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

var mapsApiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY") ?: localProperties.getProperty("MAPS_API_KEY") ?: ""

// If not in local.properties, try .env in the project root
if (mapsApiKey.isEmpty()) {
    val envFile = rootProject.file("../.env") // Project root is one level up from 'android'
    if (envFile.exists()) {
        val envProps = Properties()
        envProps.load(FileInputStream(envFile))
        mapsApiKey = envProps.getProperty("GOOGLE_MAPS_API_KEY") ?: envProps.getProperty("MAPS_API_KEY") ?: ""
    }
}


android {
    namespace = "com.anudeep.vision_aid_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.anudeep.vision_aid_app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
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
