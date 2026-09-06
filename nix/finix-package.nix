{ pkgs, terminal, widths, fontFile, fontSize ? 16, lineHeight ? 24 }:
let
  pixels = builtins.floor (fontSize * 96.0 / 72.0 + 0.5);
  face = pkgs.runCommand "cudaterm-finix-face" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pillow p.fonttools ])) ];
  } ''
    mkdir -p $out
    python3 ${../tools/build_face.py} --font ${pkgs.lib.escapeShellArg (toString fontFile)} \
      --font ${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf \
      --pixels ${toString pixels} --height ${toString lineHeight} \
      --widths ${widths} --output $out/face.bin
  '';
  wrapper = pkgs.writeShellScriptBin "cudaterm-finix" ''
    export TERMINAL=cudaterm-finix
    theme="''${XDG_CACHE_HOME:-$HOME/.cache}/wallust/colors_monstar"
    if [ -r "$theme" ]; then
      set -- --theme "$theme" "$@"
    fi
    exec ${terminal}/bin/cudaterm --font-face ${face}/face.bin --background-opacity 0.82 "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    name = "cudaterm-finix";
    desktopName = "Cudaterm";
    comment = "CUDA terminal";
    exec = "cudaterm-finix";
    icon = "utilities-terminal";
    categories = [ "System" "TerminalEmulator" ];
  };
in pkgs.symlinkJoin {
  name = "cudaterm-finix";
  paths = [ wrapper desktop ];
  passthru = { inherit face terminal; };
}
