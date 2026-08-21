#!/usr/bin/env bash

SYSCTL_FILE=/etc/sysctl.d/99-server-hardening.conf

sysctl_pairs() {
cat <<'EOF'
kernel.randomize_va_space=2
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.yama.ptrace_scope=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
}

module_sysctl_audit() {
  local k v actual
  while IFS='=' read -r k v; do
    actual="$(sysctl -n "$k" 2>/dev/null || echo unavailable)"
    printf '%-50s actual=%-8s esperado=%s\n' "$k" "$actual" "$v"
  done < <(sysctl_pairs)
  log "No se gestionan ip_forward ni rp_filter para no romper Docker/VPN/routing/multihoming."
}

module_sysctl_apply() {
  backup_path "$SYSCTL_FILE"
  [[ "$MODE" == plan ]] && { log "Escribir $SYSCTL_FILE"; return 0; }
  sysctl_pairs > "$SYSCTL_FILE"
  chmod 0644 "$SYSCTL_FILE"
  if ! sysctl --system >/dev/null; then
    error "sysctl --system fallo; revisa el backup del deployment."
    return 1
  fi
  local k v actual bad=0
  while IFS='=' read -r k v; do
    actual="$(sysctl -n "$k" 2>/dev/null || echo unavailable)"
    [[ "$actual" == "$v" ]] || { warn "sysctl $k=$actual esperado=$v"; bad=1; }
  done < <(sysctl_pairs)
  (( bad == 0 )) || return 1
}
