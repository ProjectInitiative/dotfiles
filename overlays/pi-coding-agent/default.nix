{
  channels,
  inputs,
  ...
}:
final: prev: {
  pi-coding-agent = (channels.upstream.pi-coding-agent).overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];

    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/pi \
        --run 'export NPM_CONFIG_PREFIX="$HOME/.pi/npm"' \
        --prefix PATH : ${final.lib.makeBinPath (with final; [ nodejs_latest ])}
    '';
  });
}
