import java.util.Properties

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.shadowburnv2"
    compileSdk = 36

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.shadowburnv2"
        // minSdk 23 est requis pour certaines fonctions de vibration et notifications
        minSdk = flutter.minSdkVersion 
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
        
        // Autorise l'application à dépasser la limite de 64k méthodes
        multiDexEnabled = true
    }

    compileOptions {
        // Nécessaire pour le support des fonctions Java 8+ sur vieux Android
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    buildTypes {
        getByName("release") {
            // Utilise la clé de debug pour faciliter tes tests actuels
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7")
    
    // Support des bibliothèques Java modernes (Time, etc.)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    
    // Support MultiDex pour éviter les crashs au build
    implementation("androidx.multidex:multidex:2.0.1")
}
