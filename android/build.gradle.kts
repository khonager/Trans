allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // FIX: Inject 16KB page alignment linker flags for Cargokit Rust builds
    // (irondash_engine_context compiles from Rust source via Cargokit and
    // needs -z max-page-size=16384 for Android 15+ 16KB page support)
    tasks.withType<Exec>().configureEach {
        val existing = environment["CARGO_ENCODED_RUSTFLAGS"]?.toString() ?: ""
        val separator = if (existing.isNotEmpty()) "\u001f" else ""
        environment(
            "CARGO_ENCODED_RUSTFLAGS",
            "$existing${separator}-Clink-arg=-z\u001f-Clink-arg=max-page-size=16384"
        )
    }
}

// Build directory relocation removed to fix Flutter flavor compatibility and path monitoring issues
subprojects {
    project.evaluationDependsOn(":app")

    // CRITICAL FIX: Force dependencies to use versions compatible with SDK 34
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
            force("androidx.datastore:datastore-preferences:1.1.4")
            force("androidx.datastore:datastore-core:1.1.4")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}