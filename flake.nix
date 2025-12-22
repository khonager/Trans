{
  description = "Development environment for Trans Flutter App (Android + Linux)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # 1. Das Android SDK erstellen (jetzt mit NDK!)
androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0";
          platformToolsVersion = "35.0.2";
          
          # UPDATE: Add "35.0.0"
          buildToolsVersions = [ "30.0.3" "33.0.0" "34.0.0" "35.0.0" ];
          
          includeEmulator = false;
          
          # UPDATE: Add "36"
          platformVersions = [ "33" "34" "36" ]; 
        
          includeSystemImages = false;
          useGoogleAPIs = false;
          includeExtras = [ "extras;google;gcm" ];
          
          includeNDK = true;
          # Ensure you still have the versions from the previous step
          ndkVersions = ["26.1.10909125" "27.0.12077973"]; 
        };
                androidSdk = androidComposition.androidsdk;

        linuxRuntimeLibs = with pkgs; [
          gtk3 glib pango harfbuzz cairo gdk-pixbuf atk
          xorg.libX11 xorg.libXcursor xorg.libXrandr xorg.libXinerama xorg.libXi xorg.libXext xorg.libXfixes
          libglvnd libepoxy
        ];

        nativeBuildInputs = with pkgs; [
          cmake ninja pkg-config clang git unzip which
          jdk17
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.flutter
            pkgs.dart
            pkgs.chromium
            androidSdk
          ] ++ linuxRuntimeLibs ++ nativeBuildInputs;

          shellHook = ''
export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
            export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
            
            # FIX: Point back to NDK 26
            export ANDROID_NDK_ROOT="${androidSdk}/libexec/android-sdk/ndk/26.1.10909125"
            
            export JAVA_HOME="${pkgs.jdk17}"
            
            # Update GRADLE_OPTS to use the corrected ANDROID_NDK_ROOT
            export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/libexec/android-sdk/build-tools/34.0.0/aapt2 -Dandroid.ndkPath=$ANDROID_NDK_ROOT"

            echo "🚀 Trans App Environment Ready (Android SDK + NDK 26)"       '';
        };
      }
    );
}