{ lib,
  stdenv,
  rustPlatform,
  pkgs ? stdenv.pkgs,
  ...
}: rustPlatform.buildRustPackage {
  pname = "stremio-linux-shell";
  version = "1.0.0-beta.12";

  src = pkgs.fetchFromGitHub {
    owner = "Stremio";
    repo = "stremio-linux-shell";
    rev = "28fc1cf2d3aba97c5bdd4599a269cf4e241a687a";
    hash = "sha256-cOD9sjgyZMBG7kj3J3QqIYwHr4hEckPCZ4BwFenoTvQ=";
  };

  cargoHash = "sha256-f4TpTqejR55KPSGUi47UGtHgQESUC4tnwCruy7ZfdrY=";

  buildInputs = with pkgs;
    [
      openssl
      gtk4
      libadwaita
      webkitgtk_6_0
      libepoxy
      mpv
      libappindicator
      nodejs
    ];

  nativeBuildInputs = with pkgs;
    [
      makeWrapper
      pkg-config
      gettext
    ];

  postInstall = ''
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/scalable/apps

    mv $out/bin/stremio-linux-shell $out/bin/stremio
    cp $src/data/com.stremio.Stremio.desktop $out/share/applications/com.stremio.Stremio.desktop
    cp $src/data/icons/com.stremio.Stremio.svg $out/share/icons/hicolor/scalable/apps/com.stremio.Stremio.svg

    substituteInPlace $out/share/applications/com.stremio.Stremio.desktop \
      --replace "Exec=stremio" "Exec=$out/bin/stremio"

    wrapProgram $out/bin/stremio \
       --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.libappindicator ]} \
       --prefix PATH : ${lib.makeBinPath [ pkgs.nodejs ]}'';

  meta = {
    mainProgram = "stremio";
    description = "Modern media center that gives you the freedom to watch everything you want";
    homepage = "https://www.stremio.com/";
    license = with lib.licenses; [ gpl3Only ];
    maintainers = with lib.maintainers; [ ];
    platforms = lib.platforms.linux;
  };
}
