{
  description = "Trans App Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            android_sdk.accept_license = true;
            allowUnfree = true;
          };
        };

        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;

        # Android SDK - only include emulator on Linux (not available on macOS via nix)
        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs;
          [
            cmdline-tools-latest
            build-tools-35-0-0
            platform-tools

            # Platforms
            platforms-android-36
            platforms-android-35
            platforms-android-34
            platforms-android-33
            platforms-android-31

            # Native tools
            ndk-28-0-13004108
            cmake-3-22-1
          ] ++ pkgs.lib.optionals isLinux [
            emulator
          ]
        );

        # Common environment variables
        commonEnvVars = {
          ANDROID_HOME = "${androidSdk}/share/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/share/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
        };

        # Linux-specific: Use FHS environment for binary compatibility
        linuxDevShell = pkgs.buildFHSEnv {
          name = "flutter-dev-env";
          targetPkgs = pkgs: (with pkgs; [
            androidSdk
            flutter
            jdk17

            # Common libraries needed by unpatched binaries (like aapt2)
            glibc
            pkg-config # Required for finding libraries during build
            zlib
            zlib
            ncurses5
            stdenv.cc.cc.lib
            openssl
            expat
            chromium # Added chromium for web support

            # Utilities
            glib # Fixes libglib-2.0.so.0 error for host binaries
            gtk3 # Required for file chooser and GUI elements
            gsettings-desktop-schemas # Required for file chooser settings schema
            geoclue2 # Required for geolocator
            github-cli # wrapper for git auth
            nspr
            nss
            libimobiledevice
            usbmuxd
            ifuse
          ]);

          runScript = "bash";

          profile = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
            export JAVA_HOME="${pkgs.jdk17}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.vulkan-loader ]}"
            export CHROME_EXECUTABLE="chromium"
          '';
        };

        # macOS-specific: Standard devShell (no FHS needed, binaries are native)
        darwinDevShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            androidSdk
            flutter
            jdk17
            cocoapods # Required for iOS development on macOS
          ];

          shellHook = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
            export JAVA_HOME="${pkgs.jdk17}"

            # macOS-specific: Use system Chrome or installed browser
            if [ -e "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
              export CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            elif [ -e "/Applications/Chromium.app/Contents/MacOS/Chromium" ]; then
              export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"
            fi

            echo "Flutter development environment ready!"
            echo "  ANDROID_HOME: $ANDROID_HOME"
            echo "  JAVA_HOME: $JAVA_HOME"
          '';
        };

      in
      {
        devShells.default = if isLinux then linuxDevShell.env else darwinDevShell;
      }
    );
}
