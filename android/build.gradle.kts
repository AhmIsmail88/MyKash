allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some plugins pin an older compileSdk (e.g. file_picker on android-34) while their
// transitive AndroidX dependencies require 36+. Force every module to compile against
// the same SDK as the app so AGP's AAR metadata check stays satisfied.
// Registered before evaluationDependsOn(":app") so afterEvaluate is still allowed.
subprojects {
    if (state.executed) return@subprojects
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            androidExt.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, 36)
        } catch (_: Exception) {
            // Different AGP DSL shape: leave the plugin's own value in place.
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}