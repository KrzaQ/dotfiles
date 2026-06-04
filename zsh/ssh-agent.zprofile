# Prefer the local systemd ssh-agent over any forwarded agent
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
