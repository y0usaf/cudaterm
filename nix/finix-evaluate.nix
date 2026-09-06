let
  terminal = builtins.getFlake (toString ../.);
  finix = builtins.getFlake "path:/home/y0usaf/finix";
  package = import ./finix-preview.nix;
  enabled = { user.ui.cudaterm.enable = true; };
  # Finix's wrapper already imports finixModules.default; replace its flake input
  # so this evaluates the current local module without a duplicate import.
  currentSpecialArgs = { flakeInputs = finix.inputs // { cudaterm = terminal; }; };
  desktop = finix.finixConfigurations.y0usaf-desktop.extendModules { specialArgs = currentSpecialArgs; modules = [ enabled ]; };
  framework = finix.finixConfigurations.y0usaf-framework.extendModules { specialArgs = currentSpecialArgs; modules = [ ]; };
  amd = finix.finixConfigurations.y0usaf-framework.extendModules { specialArgs = currentSpecialArgs; modules = [ enabled ]; };
  override = desktop.extendModules { modules = [ { user.defaults.terminal = "foot"; } ]; };
  failed = system: map (a: a.message) (builtins.filter (a: !a.assertion) system.config.assertions);
in assert failed desktop == [];
assert builtins.elem "cudaterm requires the NVIDIA driver" (failed amd);
assert override.config.user.defaults.terminal == "foot";
assert framework.config.user.defaults.terminal == "monstar";
assert toString desktop.config.user.ui.cudaterm.package == toString package;
{
  desktop = {
    terminal = desktop.config.user.defaults.terminal;
    environment = desktop.config.environment.variables.TERMINAL;
    launcher = desktop.config.user.defaults.launcher;
    failedAssertions = failed desktop;
    package = toString desktop.config.user.ui.cudaterm.package;
    systemDerivation = desktop.config.system.build.toplevel.drvPath;
  };
  framework = { terminal = framework.config.user.defaults.terminal; cudaterm = framework.config.user.ui.cudaterm.enable; };
  explicitOverride = override.config.user.defaults.terminal;
  amdGuard = true;
}
