# Impure local preview, using the desktop's actual configured font and metrics.
let
  terminal = builtins.getFlake (toString ../.);
  finix = builtins.getFlake "path:/home/y0usaf/finix";
  user = finix.finixConfigurations.y0usaf-desktop.config.user;
in terminal.lib.mkFinixPackage {
  fontFile = "${user.ui.fonts.mainFont}/share/fonts/truetype/DepartureMonoUltraCondensed-Regular.ttf";
  fontSize = user.appearance.termFontSize;
  lineHeight = let match = builtins.match "([0-9]+)px" user.ui.foot.lineHeight;
    in if match == null then throw "cudaterm preview requires a pixel line height"
       else builtins.fromJSON (builtins.head match);
}
