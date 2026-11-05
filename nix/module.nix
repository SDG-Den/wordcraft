# `programs.wordcraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME defaults for the whole system. NixOS cannot write per-user files, so it never
# writes `settings` either.
#
# The overlay is `settings.override.json` beside `ui.json` (`apps/wordcraft/src/main.rs`
# `load_prefs`), merged over the saved UI state at start-up. WordCraft never writes it, so the
# declarative values survive a normal save.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  wordcraftPackage ? pkgs.wordcraft,
  # `flake.nix` passes the source build and the pre-built release binary separately. Importing the
  # module directly falls back to `wordcraftPackage` and no binary.
  wordcraftSourcePackage ? wordcraftPackage,
  wordcraftBinaryPackage ? null,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.wordcraft;

  jsonFormat = pkgs.formats.json { };

  # The same list as `packaging/linux/ai.storyteller.wordcraft.desktop` (`MimeType=`).
  mimeTypes = [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/vnd.ms-word.document.macroEnabled.12"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
    "application/vnd.ms-word.template.macroEnabled.12"
    "application/msword"
    "application/msword-template"
    "application/vnd.oasis.opendocument.text"
    "application/rtf"
    "text/rtf"
    "text/markdown"
    "text/x-tex"
    "text/html"
  ];

  desktopFile = "ai.storyteller.wordcraft.desktop";

  # The per-user settings directory: `$XDG_CONFIG_HOME/wordcraft` on Linux.
  settingsDir = "${config.xdg.configHome}/wordcraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.wordcraft = {
    enable = mkEnableOption "WordCraft";

    useBinary = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install the pre-built Linux binary from `binary-url.json` when this system has one,
        instead of building from source. Falls back to the source build when the file is missing
        or the system is unsupported.
      '';
    };

    package = mkOption {
      type = types.package;
      default =
        if cfg.useBinary && wordcraftBinaryPackage != null then
          wordcraftBinaryPackage
        else
          wordcraftSourcePackage;
      defaultText = lib.literalMD "the pre-built binary from `binary-url.json`, or the source build";
      description = "The WordCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open Word documents, templates, ODT, RTF, Markdown, TeX and HTML files with WordCraft by
        default (the MIME types of `packaging/linux/ai.storyteller.wordcraft.desktop`).
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `settings.override.json`; NixOS ignores them, because it cannot write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE` by home-manager. Inert until
        theming support lands.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "wordcraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
