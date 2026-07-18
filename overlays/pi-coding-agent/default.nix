{
  channels,
  inputs,
  ...
}:
final: prev: {
  pi-coding-agent = (channels.upstream.pi-coding-agent).overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];

    postInstall = (old.postInstall or "") + ''
      target="$out/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js"

      # Patch pi-ai to strip <think> tags from content when reasoning_content
      # is also present. Some providers (cheapestinference, etc.) duplicate
      # thinking text in both fields, causing it to appear both in the
      # thinking block AND as raw text in the chat.
      ${final.nodejs_latest}/bin/node -e '
        const fs = require("fs");
        const path = process.argv[1];
        let code = fs.readFileSync(path, "utf8");

        // 1. Add inThinkSection state variable
        code = code.replace(
          "let hasFinishReason = false;",
          "let hasFinishReason = false;\n        let inThinkSection = false;"
        );

        // 2. Add hasReasoning detection after "if (!choice) continue;"
        code = code.replace(
          "                if (!choice)\n                    continue;",
          "                if (!choice)\n                    continue;\n\n                const hasReasoning = choice.delta?.reasoning_content &&\n                                     typeof choice.delta.reasoning_content === \"string\" &&\n                                     choice.delta.reasoning_content.length > 0;"
        );

        // 3. Extend the content condition to skip when hasReasoning
        code = code.replace(
          "                        choice.delta.content.length > 0) {",
          "                        choice.delta.content.length > 0 &&\n                        !hasReasoning) {"
        );

        // 4. Add think-tag stripping before ensureTextBlock
        code = code.replace(
          "                        const block = ensureTextBlock();",
          "                        var content = choice.delta.content;\n                        var textContent = content;\n                        if (inThinkSection) {\n                            var closeIdx = content.indexOf(\"</think>\");\n                            if (closeIdx >= 0) {\n                                textContent = content.slice(closeIdx + 8);\n                                inThinkSection = false;\n                                if (textContent.length === 0) continue;\n                            } else {\n                                continue;\n                            }\n                        }\n                        const block = ensureTextBlock();"
        );

        // 5. Use textContent instead of choice.delta.content
        code = code.replace(
          "                        block.text += choice.delta.content;",
          "                        block.text += textContent;"
        );

        // 6. Set inThinkSection when reasoning content is found
        code = code.replace(
          "                            const thinkingSignature = model.provider === \"opencode-go\" && foundReasoningField === \"reasoning\"",
          "                            inThinkSection = true;\n                            const thinkingSignature = model.provider === \"opencode-go\" && foundReasoningField === \"reasoning\""
        );

        fs.writeFileSync(path, code);
      ' "$target"

      wrapProgram $out/bin/pi \
        --run 'export NPM_CONFIG_PREFIX="$HOME/.pi/npm"' \
        --prefix PATH : ${final.lib.makeBinPath (with final; [ nodejs_latest ])}
    '';
  });
}
