{
  description = "cudaterm - a CUDA-rendered terminal emulator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      cuda = pkgs.cudaPackages_12_9;
      stdenv = pkgs.overrideCC pkgs.stdenv cuda.backendStdenv.cc;
      drv = stdenv.mkDerivation {
        pname = "cudaterm";
        version = "0.1.0";
        src = ./.;
        buildInputs = [ cuda.cuda_cudart cuda.cuda_nvcc pkgs.glfw pkgs.libGL pkgs.glew pkgs.kbd pkgs.freetype pkgs.unifont ];
        nativeBuildInputs = [ cuda.cuda_nvcc pkgs.gzip pkgs.patchelf ];
        buildPhase = ''
          cp ${pkgs.unifont}/share/fonts/X11/misc/unifont.pcf.gz font.pcf.gz
          nvcc -O2 -arch=sm_89 -std=c++17 -ccbin g++ \
            src/main.cu src/term.cu src/render.cu \
            -I${pkgs.glew}/include -I${pkgs.glfw}/include -I${pkgs.freetype.dev}/include \
            -lglfw -lGL -lGLEW -L${pkgs.freetype.out}/lib -lfreetype -o cudaterm
        '';
        installPhase = ''
          install -Dm755 cudaterm $out/bin/cudaterm
          install -Dm644 font.pcf.gz $out/share/cudaterm/font.pcf.gz
        '';
        postFixup = ''
          patchelf --add-rpath /run/opengl-driver/lib $out/bin/cudaterm
        '';
      };
    in {
      packages.${system}.default = drv;
      apps.${system}.default = { type = "app"; program = "${drv}/bin/cudaterm"; };
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ cuda.cuda_nvcc cuda.cuda_cudart pkgs.glfw pkgs.libGL pkgs.glew pkgs.kbd pkgs.gzip ];
      };
    };
}
