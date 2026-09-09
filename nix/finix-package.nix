{ pkgs, terminal, widths, fontCacheBuilder, fontFile, fontSize ? 16, lineHeight ? 24 }:
let
  pixels = builtins.floor (fontSize * 96.0 / 72.0 + 0.5);
  fontCache = pkgs.runCommand "cudaterm-finix-font-cache" {} ''
    mkdir -p $out
    ${fontCacheBuilder}/bin/cudaterm-build-font-cache \
      ${pkgs.lib.escapeShellArg "${fontFile}"} \
      ${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf \
      ${toString pixels} ${toString (lineHeight * 1.0 / pixels)} $out
  '';
  face = pkgs.runCommand "cudaterm-finix-face" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pillow p.fonttools ])) ];
  } ''
    mkdir -p $out
    python3 ${../tools/build_face.py} --font ${pkgs.lib.escapeShellArg "${fontFile}"} \
      --font ${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf \
      --pixels ${toString pixels} --height ${toString lineHeight} \
      --widths ${widths} --output $out/face.bin
  '';
  wrapper = pkgs.writeShellScriptBin "cudaterm-finix" ''
    export TERMINAL=cudaterm-finix
    export CUDATERM_PREPARED_FONTS=${fontCache}/cudaterm/fonts
    theme="''${XDG_CACHE_HOME:-$HOME/.cache}/wallust/colors_monstar"
    if [ -r "$theme" ]; then
      set -- --theme "$theme" "$@"
    fi
    exec ${terminal}/bin/cudaterm --font-file ${pkgs.lib.escapeShellArg "${fontFile}"} \
      --font-fallback file:${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFontMono-Regular.ttf \
      --font-size ${toString pixels} --line-height ${toString (lineHeight * 1.0 / pixels)} \
      --background-opacity 0.82 "$@"
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
  passthru = { inherit face terminal fontCache; };
}
