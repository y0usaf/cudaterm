{
  description = "CUDA terminal parser, state and rasterizer";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    cuda = pkgs.cudaPackages_12_9;
    stdenv = pkgs.overrideCC pkgs.stdenv cuda.backendStdenv.cc;
    glfw = pkgs.glfw.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ ./nix/glfw-pointer-enter.patch ./nix/glfw-primary-selection.patch ./nix/glfw-ime.patch ./nix/glfw-empty-event.patch ];
    });
    headlessSeat = pkgs.stdenv.mkDerivation {
      name = "cudaterm-headless-seat";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.weston pkgs.wayland pkgs.libxkbcommon pkgs.pixman ];
      buildPhase = ''
        $CC -shared -fPIC -Wall -Wextra -Werror ${./bench/headless_seat.c} \
          $(pkg-config --cflags --libs libweston-16 wayland-server pixman-1 xkbcommon) -o seat.so
      '';
      installPhase = "install -Dm755 seat.so $out/lib/seat.so";
    };
    fontData = pkgs.runCommand "cudaterm-unifont-17.0.05" {
      nativeBuildInputs = [ pkgs.python3 pkgs.gnutar pkgs.gzip ];
    } ''
      tar -xzf ${pkgs.unifont.src} --strip-components=1 \
        unifont-${pkgs.unifont.version}/font/precompiled/unifont-${pkgs.unifont.version}.bdf.gz \
        unifont-${pkgs.unifont.version}/font/precompiled/unifont_upper-${pkgs.unifont.version}.hex \
        unifont-${pkgs.unifont.version}/font/precompiled/unifont-combining-${pkgs.unifont.version}.txt \
        unifont-${pkgs.unifont.version}/COPYING unifont-${pkgs.unifont.version}/OFL-1.1.txt
      gzip -dc font/precompiled/unifont-${pkgs.unifont.version}.bdf.gz > unifont.bdf
      mkdir -p $out
      python3 ${./tools/build_font.py} --bdf unifont.bdf \
        --upper-hex font/precompiled/unifont_upper-${pkgs.unifont.version}.hex --out $out/font.bin
      python3 ${./tools/build_widths.py} \
        --combining font/precompiled/unifont-combining-${pkgs.unifont.version}.txt \
        --out $out/widths.bin --offsets-out $out/offsets.bin --version-out $out/unicode-version.txt
      cp COPYING OFL-1.1.txt $out/
      sed -n '/^COPYRIGHT /p' unifont.bdf > $out/font-copyright.txt
    '';
    fontRendererId = builtins.hashString "sha256" (
      builtins.readFile ./src/font.hpp + builtins.readFile ./src/font_cache.hpp
      + "${pkgs.freetype}:${stdenv.cc}"
    );
    fontCacheBuilder = stdenv.mkDerivation {
      pname = "cudaterm-font-cache-builder";
      version = "0.1.0";
      src = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [ ./src/font.hpp ./src/font_cache.hpp ./src/face.hpp ./tools/build_font_cache.cpp ];
      };
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.freetype pkgs.fontconfig pkgs.xxhash ];
      buildPhase = ''
        $CXX -O3 -std=c++17 -Isrc -DCUDATERM_DATA_DIR='"${fontData}"' \
          -DCUDATERM_FONT_CACHE_ID='"${fontRendererId}"' tools/build_font_cache.cpp \
          $(pkg-config --cflags --libs freetype2 fontconfig libxxhash) -o build-font-cache
      '';
      installPhase = "install -Dm755 build-font-cache $out/bin/cudaterm-build-font-cache";
    };
    package = stdenv.mkDerivation {
      pname = "cudaterm";
      version = "0.1.0";
      src = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [ ./src ./bench/engine_bench.cu ];
      };
      nativeBuildInputs = [ cuda.cuda_nvcc pkgs.pkg-config pkgs.patchelf pkgs.wayland-scanner ];
      buildInputs = [ cuda.cuda_cudart glfw pkgs.libGL pkgs.freetype pkgs.fontconfig pkgs.xxhash pkgs.wayland pkgs.libx11 pkgs.libxrandr ];
      buildPhase = ''
        runHook preBuild
        wayland-scanner client-header ${pkgs.wayland-protocols}/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml xdg-activation-v1-client-protocol.h
        wayland-scanner private-code ${pkgs.wayland-protocols}/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml xdg-activation-v1-protocol.c
        $CC -O2 -c xdg-activation-v1-protocol.c -o xdg-activation-v1.o
        nvcc -O3 -lineinfo -std=c++17 -arch=sm_89 -I src -DCUDATERM_DATA_DIR='"${fontData}"' -c src/engine.cu -o engine.o
        nvcc -O3 -std=c++17 -arch=sm_89 -I src -I . -DCUDATERM_DATA_DIR='"${fontData}"' -DCUDATERM_FONT_CACHE_ID='"${fontRendererId}"' -DCUDATERM_XDG_OPEN='"${pkgs.xdg-utils}/bin/xdg-open"' src/main.cu engine.o xdg-activation-v1.o \
          $(pkg-config --cflags --libs glfw3 gl freetype2 fontconfig libxxhash wayland-client x11) -lutil -o cudaterm
        nvcc -O3 -std=c++17 -arch=sm_89 -I src bench/engine_bench.cu engine.o -o engine-bench
        runHook postBuild
      '';
      installPhase = ''
        mkdir -p $out/share
        ln -s ${fontData} $out/share/cudaterm
        install -Dm755 cudaterm $out/bin/cudaterm
        install -Dm755 engine-bench $out/bin/cudaterm-engine-bench
      '';
      postFixup = ''
        for exe in $out/bin/*; do
          patchelf --add-rpath /run/opengl-driver/lib "$exe"
        done
      '';
    };
  in {
    lib.mkFinixPackage = args: import ./nix/finix-package.nix ({
      inherit pkgs fontCacheBuilder;
      terminal = package;
      widths = "${fontData}/widths.bin";
    } // args);
    finixModules.default = import ./nix/finix-module.nix;
    packages.${system} = { default = package; headless-seat = headlessSeat; };
    apps.${system} = {
    default = { type = "app"; program = "${package}/bin/cudaterm"; };
    startup-benchmark = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-startup-benchmark" ''
      exec ${pkgs.python3}/bin/python3 ${./bench/startup.py} \
        --weston ${pkgs.weston}/bin/weston --seat ${headlessSeat}/lib/seat.so "$@"
    ''}"; };
    build-face = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-build-face" ''
      exec ${pkgs.python3.withPackages (p: [ p.pillow p.fonttools ])}/bin/python3 ${./tools/build_face.py} "$@"
    ''}"; };
    bench = { type = "app"; program = "${package}/bin/cudaterm-engine-bench"; };
    };
    checks.${system} = { build = package; };
    devShells.${system}.default = pkgs.mkShell.override { inherit stdenv; } {
      inputsFrom = [ package ];
      packages = [ pkgs.python3 ];
    };
  };
}
