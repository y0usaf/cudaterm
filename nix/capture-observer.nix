let
  project = builtins.getFlake (toString ../.);
  pkgs = import project.inputs.nixpkgs { system = "x86_64-linux"; };
in pkgs.stdenv.mkDerivation {
  name = "cudaterm-private-capture-observer";
  dontUnpack = true;
  nativeBuildInputs = [ pkgs.pkg-config pkgs.wayland-scanner ];
  buildInputs = [ pkgs.wayland pkgs.libdrm ];
  buildPhase = ''
    wayland-scanner client-header ${pkgs.weston.src}/protocol/weston-output-capture.xml capture-client.h
    wayland-scanner private-code ${pkgs.weston.src}/protocol/weston-output-capture.xml capture-code.c
    $CC -O2 -Wall -Wextra -Werror -I. ${../bench/capture_observer.c} capture-code.c \
      $(pkg-config --cflags --libs wayland-client libdrm) -o capture-observer
  '';
  installPhase = "install -Dm755 capture-observer $out/bin/capture-observer";
}
