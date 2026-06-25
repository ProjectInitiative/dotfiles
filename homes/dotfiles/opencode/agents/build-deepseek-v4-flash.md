---
description: Fast implementation subagent using DeepSeek V4 Flash for writing code, editing files, and implementing features
model: opencode-go/deepseek-v4-flash
mode: subagent
permission:
  edit: allow
  bash: ask
  read: allow
  glob: allow
  grep: allow
  todowrite: allow
---

Fast implementation subagent for writing code, editing files, and building features. Use this for straightforward implementation tasks where speed matters and the task doesn't require complex reasoning. Writes clean, idiomatic code following existing project conventions.
