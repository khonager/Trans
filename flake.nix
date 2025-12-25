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
          libepoxy # Changed from 'epoxy' to 'libepoxy' which is the standard name in nixpkgs
          
          # NEW: Required for Supabase Auth & Shared Preferences
          libsecret 
          jsoncpp
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            flutter
            jdk17
            git
          ] ++ buildLibs;

          # Critical: Set LD_LIBRARY_PATH so the compiled app can find libsecret at runtime
          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath buildLibs}:$LD_LIBRARY_PATH
            export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"
            
            echo "Flutter Dev Shell Entered."
            echo "Dependencies (libsecret, jsoncpp) added to LD_LIBRARY_PATH."
          '';
        };
      }
    );
}