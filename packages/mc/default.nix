{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  glib,
  gpm,
  file,
  e2fsprogs,
  xorg ? null,
  perl,
  zip,
  unzip,
  gettext,
  slang,
  libssh2,
  openssl,
  aspell,
  autoconf,
  automake,
  libtool,
}:

stdenv.mkDerivation rec {
  pname = "mc";
  version = "4.8.30"; # Update this to the latest version as needed

  src = fetchFromGitHub {
    owner = "MidnightCommander";
    repo = "mc";
    rev = "${version}";
    hash = "sha256-8yGqbEFZ0ySU+xbHH/ECxiIsTNqd7xGhI0smAct6MQg=";
  };

  nativeBuildInputs = [
    pkg-config
    autoconf
    automake
    libtool
    gettext
  ];

  buildInputs =
    [
      glib
      gpm
      file
      e2fsprogs
      perl
      zip
      unzip
      slang
      libssh2
      openssl
      aspell
    ]
    ++ lib.optionals (xorg != null) [
      xorg.libX11
      xorg.libICE
    ];

  enableParallelBuilding = true;

  configureFlags = [
    "--with-screen=slang"
    "--enable-aspell"
    "--enable-charset"
    "--enable-vfs-sftp"
  ] ++ lib.optional (xorg != null) "--with-x";

  preConfigure = ''
    ./autogen.sh
  '';

  meta = with lib; {
    description = "GNU Midnight Commander is a visual file manager";
    homepage = "https://midnight-commander.org/";
    downloadPage = "https://midnight-commander.org/downloads";
    license = licenses.gpl3Plus;
    platforms = platforms.unix;
    maintainers = with maintainers; [ ];
  };
}
