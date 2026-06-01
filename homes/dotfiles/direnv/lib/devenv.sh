use_devenv() {
  watch_file .envrc devenv.nix devenv.lock devenv.yaml
  eval "$(devenv direnv-export)"
}
