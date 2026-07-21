# Prefer the local systemd ssh-agent over any forwarded agent.
# In a limes sandbox, keep the agent limes forwards instead (its socket, not this one).
[[ -z "$LIMES_VERSION" ]] && export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
