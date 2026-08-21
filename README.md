# Linux Server Hardening

Baseline modular de hardening para servidores Linux orientado a produccion. Implementa auditoria, plan, aplicacion por modulo, snapshots por deployment, rollback conservador y reporte.

## Distribuciones objetivo

- Debian
- Ubuntu
- AlmaLinux
- Rocky Linux
- RHEL

> `v7.0.0-rc1`: la logica multi-distro esta implementada, pero debe validarse en staging en cada version objetivo antes de declararla soportada en produccion.

## Inicio rapido

```bash
cp config/local.conf.example config/local.conf
sudo ./hardening.sh audit
sudo ./hardening.sh plan
sudo ./hardening.sh first-deploy
```

Aplicacion modular:

```bash
sudo ./hardening.sh apply ssh
sudo ./hardening.sh apply logging
sudo ./hardening.sh apply docker
```

Rollback:

```bash
sudo ./hardening.sh rollback list
sudo ./hardening.sh rollback latest
sudo ./hardening.sh rollback latest ssh
```

## Salvaguardas clave

- No desactiva password SSH si `ADMIN_USER` no tiene `authorized_keys` utilizable.
- No gestiona firewall local por defecto.
- No fuerza `ip_forward` ni `rp_filter`.
- SELinux Disabled se prepara como Permissive + autorelabel; no salta directamente a Enforcing.
- No genera `audit2allow` automaticamente.
- No reinicia Docker automaticamente si hay contenedores activos (`auto`).
- No ejecuta `logrotate -f` sobre fragmentos.
- Rollback crea un checkpoint pre-rollback y valida configuraciones despues.
- No elimina paquetes ni usuarios automaticamente durante rollback.

## Documentacion completa

La documentacion tecnica esta preparada para la **GitHub Wiki** en el paquete `Linux-server-hardening.wiki` entregado junto al repositorio.
