{
  description = "Flutter Travel Companion Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.android_sdk.accept_license = true;
        };
        
        # Libraries required for Flutter Linux Desktop
        buildLibs = with pkgs; [
          pkg-config
          cmake
          ninja
          gtk3
          glib
          pcre
          util-linux
          libselinux
          libsepol
          libthai
          libdatrie
          xorg.libXdmcp
          xorg.libXtst
          libxkbcommon
          dbus
          at-spi2-core
          libepoxy
          
          # NEW: Required for Supabase Auth & Shared Preferences
          libsecret 
          jsoncpp
          
          # Fix for "sysprof-capture-4 not found" error
          sysprof
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          # nativeBuildInputs is often better for tools like pkg-config
          nativeBuildInputs = with pkgs; [
            pkg-config
            cmake
            ninja
          ];

          buildInputs = with pkgs; [
            flutter
            jdk17
            git
          ] ++ buildLibs;

          # Critical: Set LD_LIBRARY_PATH so the compiled app can find libsecret at runtime
          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath buildLibs}:$LD_LIBRARY_PATH
            export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"
            
            # Explicitly add PKG_CONFIG_PATH for sysprof to avoid the build error
            # We add both lib/pkgconfig and share/pkgconfig just in case
            export PKG_CONFIG_PATH=${pkgs.sysprof}/lib/pkgconfig:${pkgs.sysprof}/share/pkgconfig:$PKG_CONFIG_PATH
            
            echo "Flutter Dev Shell Entered."
            echo "Dependencies (libsecret, jsoncpp, sysprof) added to LD_LIBRARY_PATH."
          '';
        };
      }
    );
}