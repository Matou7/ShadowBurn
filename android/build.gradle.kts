allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force le dossier de build pour que Flutter ne soit pas perdu
val newBuildDir = File(rootProject.projectDir, "../build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val subprojectBuildDir = File(newBuildDir, project.name)
    project.layout.buildDirectory.set(subprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
