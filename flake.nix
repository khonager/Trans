{
  description = "Development environment for Trans Flutter App";

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

        # 1. Libraries required for building the Linux Desktop target
        # These are linked dynamically when you run `flutter run -d linux`
        linuxRuntimeLibs = with pkgs; [
          gtk3
          glib
          pango
          harfbuzz
          cairo
          gdk-pixbuf
          atk

          # X11 & OpenGL basics
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXinerama
          xorg.libXi
          xorg.libXext
          xorg.libXfixes
          libglvnd
          libepoxy
        ];

        # 2. Build tools required by CMake/Ninja
        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          pkg-config
          clang
          git
          unzip
          which
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          # Packages available in the shell
          buildInputs = [
            pkgs.flutter
            pkgs.dart
            pkgs.chromium # For web debugging
          ] ++ linuxRuntimeLibs ++ nativeBuildInputs;

          # 3. Environment Configuration
          shellHook = ''
            # Fix for Flutter unable to find Linux libraries on NixOS
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath linuxRuntimeLibs}:$LD_LIBRARY_PATH
            
            # Tell Flutter where Chrome is (for web builds)
            export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"

            # Welcome Message
            echo "================================================="
            echo " 🚅 Trans App - Flutter Dev Environment (NixOS) "
            echo "================================================="
            echo " Commands available:"
            echo "   flutter run -d linux   (Native Linux App)"
            echo "   flutter run -d chrome  (Web App)"
            echo "================================================="
          '';
        };
      }
    );
}
