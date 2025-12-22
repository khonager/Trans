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
          
          # Platforms required by various plugins
          platforms-android-36
          platforms-android-35
          platforms-android-34
          platforms-android-33
          
          # Native development tools
          ndk-27-0-12077973
          cmake-3-22-1       # FIX: Added CMake 3.22.1
          
          emulator
        ]);

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            flutter
            jdk17
            androidSdk
          ];

          ANDROID_HOME = "${androidSdk}/share/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/share/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          
          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [ pkgs.vulkan-loader ]}";
        };
      }
    );
}