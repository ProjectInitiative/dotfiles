{
  channels,
  inputs,
  ...
}:
final: prev: {
  inherit (channels.upstream) pi-coding-agent;
}
