{
  description = "CUDA terminal parser, state and rasterizer";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    cuda = pkgs.cudaPackages_12_9;
    stdenv = pkgs.overrideCC pkgs.stdenv cuda.backendStdenv.cc;
    # GLFW 3.4 discards the coordinates supplied by Wayland pointer enter.
    # Deliver them before a click can start selection with stale coordinates.
    glfw = pkgs.glfw.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ ./nix/glfw-pointer-enter.patch ];
    });
    headlessSeat = pkgs.stdenv.mkDerivation {
      name = "cudaterm-headless-seat";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.weston pkgs.wayland pkgs.libxkbcommon pkgs.pixman ];
      buildPhase = ''
        $CC -shared -fPIC -Wall -Wextra -Werror ${./tests/headless_seat.c} \
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
    testTerminal = pkgs.writeShellScript "cudaterm-test-terminal" ''
      exec ${package}/bin/cudaterm --no-config --font-family bitmap --theme classic --padding-x 0 --padding-y 0 "$@"
    '';
    package = stdenv.mkDerivation {
      pname = "cudaterm";
      version = "0.1.0";
      src = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.intersection
          (pkgs.lib.fileset.fileFilter (file: ! file.hasExt "pyc") ./.)
          (pkgs.lib.fileset.unions [ ./src ./tests ./tools ./data ./bench/pty_throughput.py ./bench/visible_output.py ./bench/private_baseline.py ./bench/engine_bench.cu ]);
      };
      nativeBuildInputs = [ cuda.cuda_nvcc pkgs.pkg-config pkgs.patchelf pkgs.python3 ];
      buildInputs = [ cuda.cuda_cudart glfw pkgs.glew pkgs.libGL pkgs.libvterm-neovim pkgs.freetype pkgs.fontconfig ];
      buildPhase = ''
        runHook preBuild
        nvcc -O3 -lineinfo -std=c++17 -arch=sm_89 -I src -DCUDATERM_DATA_DIR='"${fontData}"' -c src/engine.cu -o engine.o
        nvcc -O3 -std=c++17 -arch=sm_89 -I src -DCUDATERM_DATA_DIR='"${fontData}"' -DCUDATERM_XDG_OPEN='"${pkgs.xdg-utils}/bin/xdg-open"' src/main.cu engine.o \
          $(pkg-config --cflags --libs glfw3 glew freetype2 fontconfig) -lutil -o cudaterm
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/engine_test.cu engine.o -o engine-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/appearance_test.cu engine.o -o appearance-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/memory_probe.cu engine.o -lEGL -lGL -o memory-probe
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/engine_host.cu engine.o -o engine-host
        nvcc -O3 -std=c++17 -arch=sm_89 -I src bench/engine_bench.cu engine.o -o engine-bench
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/plain_test.cu engine.o -o plain-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/vt_test.cu engine.o -o vt-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/unicode_test.cu engine.o -o unicode-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/csi_test.cu engine.o -o csi-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/styled_test.cu engine.o -o styled-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/workspace_test.cu engine.o -o workspace-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/reflow_test.cu engine.o -o reflow-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/search_test.cu engine.o -o search-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/search_cost.cu engine.o -o search-cost
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/selection_test.cu engine.o -o selection-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/scrollback_test.cu engine.o -o scrollback-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/charset_test.cu engine.o -o charset-test
        nvcc -O3 -std=c++17 -arch=sm_89 -I src tests/mouse_test.cu engine.o -o mouse-test
        nvcc -O3 -std=c++17 -I src tests/reference_test.cu engine.o \
          $(pkg-config --cflags --libs vterm) -o reference-test
        $CXX -O2 -std=c++17 -Isrc tests/input_test.cpp -o input-test
        $CXX -O2 -std=c++17 -Isrc -DCUDATERM_DATA_DIR='"${fontData}"' tests/font_test.cpp \
          $(pkg-config --cflags --libs freetype2 fontconfig) -o font-test
        runHook postBuild
      '';
      doCheck = true;
      checkPhase = ''
        python3 tests/test_benchmark.py
        python3 tests/test_visible_output.py
        python3 tests/test_private_baseline.py
        python3 tests/test_window_cleanup.py
        python3 tests/test_font.py
        python3 tests/test_widths.py
        python3 tools/build_emoji_vs16.py data/emoji-variation-sequences-17.0.0.txt --check src/emoji_vs16.cuh
        python3 tools/build_emoji_modifiers.py data/emoji-data-17.0.0.txt --check src/emoji_modifiers.cuh
        python3 tools/build_grapheme_properties.py --check
        python3 tests/test_grapheme_properties.py
        ./input-test
        ./font-test ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
          ${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf
      '';
      installPhase = ''
        mkdir -p $out/share
        ln -s ${fontData} $out/share/cudaterm
        install -Dm755 cudaterm $out/bin/cudaterm
        install -Dm755 engine-test $out/bin/cudaterm-engine-test
        install -Dm755 appearance-test $out/bin/cudaterm-appearance-test
        install -Dm755 memory-probe $out/bin/cudaterm-memory-probe
        install -Dm755 engine-host $out/bin/cudaterm-engine-host
        install -Dm755 unicode-test $out/bin/cudaterm-unicode-test
        install -Dm755 csi-test $out/bin/cudaterm-csi-test
        install -Dm755 styled-test $out/bin/cudaterm-styled-test
        install -Dm755 workspace-test $out/bin/cudaterm-workspace-test
        install -Dm755 reflow-test $out/bin/cudaterm-reflow-test
        install -Dm755 search-test $out/bin/cudaterm-search-test
        install -Dm755 search-cost $out/bin/cudaterm-search-cost
        install -Dm755 selection-test $out/bin/cudaterm-selection-test
        install -Dm755 mouse-test $out/bin/cudaterm-mouse-test
        install -Dm755 charset-test $out/bin/cudaterm-charset-test
        install -Dm755 scrollback-test $out/bin/cudaterm-scrollback-test
        install -Dm755 reference-test $out/bin/cudaterm-reference-test
        install -Dm755 vt-test $out/bin/cudaterm-vt-test
        install -Dm755 plain-test $out/bin/cudaterm-plain-test
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
      inherit pkgs;
      terminal = package;
      widths = "${fontData}/widths.bin";
    } // args);
    finixModules.default = import ./nix/finix-module.nix;
    packages.${system} = { default = package; headless-seat = headlessSeat; };
    apps.${system} = {
    default = { type = "app"; program = "${package}/bin/cudaterm"; };
    appearance-test = { type = "app"; program = "${package}/bin/cudaterm-appearance-test"; };
    build-face = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-build-face" ''
      exec ${pkgs.python3.withPackages (p: [ p.pillow p.fonttools ])}/bin/python3 ${./tools/build_face.py} "$@"
    ''}"; };
    unicode-test = { type = "app"; program = "${package}/bin/cudaterm-unicode-test"; };
    csi-test = { type = "app"; program = "${package}/bin/cudaterm-csi-test"; };
    styled-test = { type = "app"; program = "${package}/bin/cudaterm-styled-test"; };
    workspace-test = { type = "app"; program = "${package}/bin/cudaterm-workspace-test"; };
    reflow-test = { type = "app"; program = "${package}/bin/cudaterm-reflow-test"; };
    search-test = { type = "app"; program = "${package}/bin/cudaterm-search-test"; };
    search-cost = { type = "app"; program = "${package}/bin/cudaterm-search-cost"; };
    selection-test = { type = "app"; program = "${package}/bin/cudaterm-selection-test"; };
    mouse-test = { type = "app"; program = "${package}/bin/cudaterm-mouse-test"; };
    charset-test = { type = "app"; program = "${package}/bin/cudaterm-charset-test"; };
    scrollback-test = { type = "app"; program = "${package}/bin/cudaterm-scrollback-test"; };
    reference-test = { type = "app"; program = "${package}/bin/cudaterm-reference-test"; };
    vt-test = { type = "app"; program = "${package}/bin/cudaterm-vt-test"; };
    plain-test = { type = "app"; program = "${package}/bin/cudaterm-plain-test"; };
    bench = { type = "app"; program = "${package}/bin/cudaterm-engine-bench"; };
    test = { type = "app"; program = "${package}/bin/cudaterm-engine-test"; };
    memory-probe = { type = "app"; program = "${package}/bin/cudaterm-memory-probe"; };
    engine-host = { type = "app"; program = "${package}/bin/cudaterm-engine-host"; };
    graphics-test = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-graphics-test" ''
      exec ${pkgs.python3}/bin/python3 ${./tests/test_graphics.py} --host ${package}/bin/cudaterm-engine-host
    ''}"; };
    headless-test = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-headless-test" ''
      exec ${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./tests/window_headless.py} \
        --weston ${pkgs.weston}/bin/weston --seat ${headlessSeat}/lib/seat.so \
        --terminal ${testTerminal} --idle-probe ${./bench/idle_resources.py} "$@"
    ''}"; };
    sync-test = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-sync-test" ''
      export PYTHONPATH=${./tests}
      exec ${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./tests/window_sync.py} \
        --weston ${pkgs.weston}/bin/weston --seat ${headlessSeat}/lib/seat.so \
        --terminal ${testTerminal} --wl-copy ${pkgs.wl-clipboard}/bin/wl-copy "$@"
    ''}"; };
    window-appearance-test = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-window-appearance-test" ''
      export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }}
      exec ${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./tests/window_appearance.py} \
        --weston ${pkgs.weston}/bin/weston --seat ${headlessSeat}/lib/seat.so \
        --terminal ${package}/bin/cudaterm --wl-paste ${pkgs.wl-clipboard}/bin/wl-paste "$@"
    ''}"; };
    window-search-test = { type = "app"; program = "${pkgs.writeShellScript "cudaterm-window-search-test" ''
      export PYTHONPATH=${./tests}
      exec ${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./tests/window_search.py} \
        --weston ${pkgs.weston}/bin/weston --seat ${headlessSeat}/lib/seat.so \
        --terminal ${testTerminal} --wl-copy ${pkgs.wl-clipboard}/bin/wl-copy "$@"
    ''}"; };
    };
    checks.${system}.build = package;
    devShells.${system}.default = pkgs.mkShell.override { inherit stdenv; } {
      inputsFrom = [ package ];
      packages = [ pkgs.python3 ];
    };
  };
}
