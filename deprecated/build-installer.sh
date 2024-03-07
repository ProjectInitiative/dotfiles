#!/usr/bin/env bash

DEVENV=".functions/devenv"


cat << EOF > install.sh
#!/usr/bin/env bash

\mkdir -p "\$HOME/.functions"

DEVENV="$DEVENV"

\touch "\$HOME/.bashrc" && \grep -qF '\$DEVENV' "\$HOME/.bashrc" || printf "\nif [[ -f \$HOME/\$DEVENV ]]; then\n    source \$HOME/\$DEVENV\nfi\n" >> "\$HOME/.bashrc"

cat << EOF | base64 --decode > \$HOME/\$DEVENV
$(base64 $DEVENV)
$(echo EOF)
EOF

chmod +x install.sh
