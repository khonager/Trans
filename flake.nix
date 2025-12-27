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

        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-35-0-0
          platform-tools

          # Platforms
          platforms-android-36
          platforms-android-35
          platforms-android-34
          platforms-android-33

          # Native tools
          ndk-27-0-12077973
          cmake-3-22-1

          emulator
        ]);

        fhs = pkgs.buildFHSEnv {
          name = "flutter-dev-env";
          targetPkgs = pkgs: (with pkgs; [
            androidSdk
            flutter
            jdk17

            # Common libraries needed by unpatched binaries (like aapt2)
            glibc
            zlib
            ncurses5
            stdenv.cc.cc.lib # FIX: Replaces 'stdcxx'
            openssl
            expat
            chromium # Added chromium for web support
          ]);

          runScript = "bash";

          profile = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="${androidSdk}/share/android-sdk"
            export JAVA_HOME="${pkgs.jdk17}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.vulkan-loader ]}"
            export CHROME_EXECUTABLE="chromium" # Tell Flutter where to find the browser
          '';
        };

      in
      {
        devShells.default = fhs.env;
      }
    );
}
