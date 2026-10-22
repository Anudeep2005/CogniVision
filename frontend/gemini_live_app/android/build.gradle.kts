import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")

    // The tflite_flutter plugin sets Java compileOptions to 11 but omits a Kotlin JVM target,
    // which causes KGP 2.x on JDK 17 to default Kotlin to JVM 17.
    // Explicitly align tflite_flutter's Kotlin task to its declared Java 11 target
    // without overriding other plugins (e.g., camera_android_camerax) that declare JVM 17.
    if (project.name == "tflite_flutter") {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_11)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

