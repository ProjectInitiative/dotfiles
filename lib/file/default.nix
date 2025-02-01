{ lib, inputs, ... }:

rec {
  ## Append text to the contents of a file
  ##
  ## ```nix
  ## fileWithText ./some.txt "appended text"
  ## ```
  ##
  #@ Path -> String -> String
  fileWithText = file: text: ''
    ${builtins.readFile file}
    ${text}'';

  ## Prepend text to the contents of a file
  ##
  ## ```nix
  ## fileWithText' ./some.txt "prepended text"
  ## ```
  ##
  #@ Path -> String -> String
  fileWithText' = file: text: ''
    ${text}
    ${builtins.readFile file}'';

  getFileExt =
    file:
    let
      parts = lib.splitString "." file;
      len = builtins.length parts;
    in
    if len > 1 then builtins.elemAt parts (len - 1) else throw "File has no extension: ${file}";

  ## Read and parse a file as either YAML or JSON based on extension
  ##
  ## Automatically detects file type based on extension (.yaml, .yml, or .json)
  ## and parses accordingly. Uses yj to convert YAML to JSON when needed.
  ##
  ## ```nix
  ## readYAMLOrJSON ./config.yaml   # reads YAML
  ## readYAMLOrJSON ./config.json   # reads JSON directly
  ## ```
  ##
  #@ Path -> AttrSet
  # readYAMLOrJSONFile = file:
  # let
  #   ext = getFileExt file;
  #   contents = builtins.readFile file;
  # in
  #   if ext == "json"
  #   then builtins.fromJSON contents
  #   else if ext == "yaml" || ext == "yml"
  #   then
  #     builtins.fromJSON (
  #       builtins.readFile (
  #         inputs.pkgs.runCommand "yaml-to-json" {
  #           buildInputs = [ inputs.pkgs.yj ];
  #         } ''
  #           yj -yj < ${file} > $out
  #         ''
  #       )
  #     )
  #   else throw "Unsupported file format: ${ext}";

  # readYAMLOrJSONRaw =
  #   content:
  #   let
  #     parseResult =
  #       inputs.nixpkgs.legacyPackages.${pkgs.system}.runCommand "parse-yaml-or-json"
  #         {
  #           inherit content;
  #           nativeBuildInputs = [
  #             inputs.nixpkgs.legacyPackages.${pkgs.system}.yq-go
  #             inputs.nixpkgs.legacyPackages.${pkgs.system}.jq
  #           ];

  #         }
  #         ''
  #           # First try parsing as JSON using jq
  #           if echo "$content" | jq '.' >/dev/null 2>&1; then
  #             # If it's valid JSON, just format it
  #             echo "$content" | jq '.' > $out
  #           else
  #             # If JSON fails, try YAML
  #             echo "$content" > ./input.yml
  #             if ! yq -o=json eval ./input.yml > $out 2>/dev/null; then
  #               echo "Error: Content is neither valid JSON nor valid YAML" >&2
  #               exit 1
  #             fi
  #           fi
  #         '';
  #   in
  #   builtins.fromJSON (builtins.readFile parseResult);

    # Create a function that takes pkgs as an argument
  mkParseYAMLOrJSON = pkgs: content:
    let
      parseResult =
        pkgs.runCommand "parse-yaml-or-json"
          {
            inherit content;
            nativeBuildInputs = [
              pkgs.yq-go
              pkgs.jq
            ];
          }
          ''
            # First try parsing as JSON using jq
            if echo "$content" | jq '.' >/dev/null 2>&1; then
              # If it's valid JSON, just format it
              echo "$content" | jq '.' > $out
            else
              # If JSON fails, try YAML
              echo "$content" > ./input.yml
              if ! yq -o=json eval ./input.yml > $out 2>/dev/null; then
                echo "Error: Content is neither valid JSON nor valid YAML" >&2
                exit 1
              fi
            fi
          '';
    in
    builtins.fromJSON (builtins.readFile parseResult);

}
