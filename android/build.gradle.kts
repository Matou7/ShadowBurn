import com.android.build.api.dsl.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = File(rootProject.projectDir, "../build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val subprojectBuildDir = File(newBuildDir, project.name)
    project.layout.buildDirectory.set(subprojectBuildDir)
}

subprojects {
    afterEvaluate {
        extensions.findByType<LibraryExtension>()?.apply {
            compileSdk = 37
        }
    }
    if (path != ":app") {
        evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}