{ lib, ... }:
let
  # US formatting, Polish locale for everything personal.
  plCategories = [
    "ADDRESS"
    "IDENTIFICATION"
    "MEASUREMENT"
    "MONETARY"
    "NAME"
    "NUMERIC"
    "PAPER"
    "TELEPHONE"
    "TIME"
  ];
in
{
  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = lib.genAttrs (map (category: "LC_${category}") plCategories) (
    _: "pl_PL.UTF-8"
  );

  services.xserver.xkb.layout = "pl";

  console.keyMap = "pl2";
}
