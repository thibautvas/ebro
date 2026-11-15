{
  lib,
  stdenv,
  fetchgit,
  zig_0_17,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
  configFile ? null,
}:

let
  zigWayland = {
    hash = "wayland-0.8.0-dev-lQa1kuf8AQCeoam8G-XPyaIYvIOk3_wgsspwi4nT_L5q";
    src = fetchgit {
      url = "https://codeberg.org/ifreund/zig-wayland";
      rev = "94db7ba4e0a6b4780a16dbc74c7a2c88f1ebf502";
      hash = "sha256-vuro4OJOIjgBvL8dbOF4HyXmem71l7PKx5SJMeRk0N4=";
    };
  };

in
stdenv.mkDerivation {
  pname = "ebro";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../src
      ../protocol
    ];
  };

  strictDeps = true;

  nativeBuildInputs = [
    zig_0_17
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    wayland-scanner
    wayland-protocols
  ];

  postPatch = lib.optionalString (configFile != null) ''
    cp ${configFile} src/config.zig
  '';

  postConfigure = ''
    mkdir -p zig-pkg
    cp -r ${zigWayland.src} zig-pkg/${zigWayland.hash}
    chmod -R u+w zig-pkg
  '';

  meta = {
    description = "Minimal tiling window manager for the river Wayland compositor";
    license = lib.licenses.mit;
    mainProgram = "ebro";
    platforms = lib.platforms.linux;
  };
}
