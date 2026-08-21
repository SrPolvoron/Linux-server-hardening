# Linux Server Hardening

Baseline modular y conservador de hardening para servidores Linux orientado a entornos de produccion.

El proyecto automatiza la auditoria y aplicacion de controles de seguridad sobre SSH, usuarios, logging, auditd, sysctl, sincronizacion horaria, SELinux/AppArmor, Fail2ban, Docker y otros componentes habituales, intentando evitar cambios genericos que puedan romper routing, VPN, contenedores o servicios existentes.

> **Estado actual: `v7.0.0-rc1`**  
> La arquitectura multi-distro esta implementada. AlmaLinux 9 ha sido utilizado para validacion funcional real. Debian, Ubuntu, Rocky Linux y RHEL deben completar la matriz de staging antes de considerarse validados para produccion.

## Objetivos

- Aplicar un baseline de seguridad reproducible y auditable.
- Detectar el estado real antes de modificar el sistema.
- Separar auditoria, planificacion y aplicacion.
- Evitar cambios destructivos o incompatibles con cargas de produccion.
- Crear backups por deployment antes de modificar configuracion.
- Permitir rollback por deployment y por modulo.
- Validar cada cambio antes de considerarlo aplicado.
- Facilitar una futura migracion del baseline a Ansible.
- Servir como base tecnica de hardening para entornos con requisitos de seguridad elevados, incluido ENS, sin afirmar que el script por si solo proporciona conformidad ENS.

## Distribuciones objetivo

| Familia | Distribuciones |
|---|---|
| Debian | Debian, Ubuntu |
| RHEL | AlmaLinux, Rocky Linux, Red Hat Enterprise Linux |

La deteccion del gestor de paquetes se realiza por **familia de distribucion**, no por la mera presencia de binarios como `apt-get`, `dnf` o `yum`.

Esto evita, por ejemplo, que un AlmaLinux con `apt-get` instalado accidentalmente sea tratado como Debian.

## Modulos

| Modulo | Funcion |
|---|---|
| `user` | Usuario administrador, grupos administrativos y acceso Docker opcional |
| `ssh` | Hardening de OpenSSH, claves, puerto, root login, password auth y timeouts |
| `banner` | Avisos legales/pre-login y MOTD |
| `auditd` | Auditoria de cambios sensibles y politica de rotacion |
| `logging` | journald persistente, limites de espacio, rsyslog y logrotate |
| `ntp` | Sincronizacion horaria mediante chrony |
| `sysctl` | Parametros de kernel y red seguros para servidores genericos |
| `selinux` | SELinux en sistemas RHEL-like, puertos SSH y transicion segura de modos |
| `apparmor` | Comprobaciones de AppArmor en Debian/Ubuntu |
| `extras` | Fail2ban, Etckeeper y componentes auxiliares |
| `docker` | Logging del daemon, validacion y comprobaciones de runtime |
| `report` | Informe persistente del estado del host |
| `rollback` | Restauracion conservadora por deployment o modulo |

## Principios de seguridad

El proyecto no intenta aplicar controles agresivos a ciegas.

Algunas decisiones deliberadas:

- No desactiva la autenticacion SSH por password si el usuario administrador no dispone de una `authorized_keys` utilizable.
- No habilita `PermitRootLogin`.
- No gestiona el firewall local por defecto.
- No fuerza `net.ipv4.ip_forward` ni `rp_filter`, porque pueden romper Docker, VPN, routing o hosts multihomed.
- No pasa SELinux directamente de `Disabled` a `Enforcing`.
- No genera reglas `audit2allow` automaticamente.
- No reinicia Docker automaticamente si detecta workloads activos cuando la politica esta en `auto`.
- No ejecuta `logrotate -f` directamente sobre fragmentos de `/etc/logrotate.d/`.
- No elimina usuarios ni paquetes automaticamente durante rollback.
- No habilita repositorios externos silenciosamente.
- No oculta errores criticos de validacion durante rollback.

## Requisitos

Ejecutar como `root` o mediante `sudo`.

Requisitos basicos:

```text
bash
systemd
git
utilidades GNU habituales
```

Las dependencias especificas de cada modulo se comprueban antes de utilizarlas. Cuando una dependencia es obligatoria y esta disponible en los repositorios habilitados, el modulo puede instalarla. Las dependencias opcionales no provocan una modificacion de repositorios sin consentimiento explicito.

Ejemplos de dependencias gestionadas:

- `openssh-server`
- `chrony`
- `audit`
- `rsyslog`
- `logrotate`
- `rsyslog-logrotate` en RHEL-like cuando aplica
- `policycoreutils-python-utils` para `semanage`
- `apparmor-utils` en Debian/Ubuntu cuando aplica
- `fail2ban`
- `etckeeper`
- `nftables`

Consulta la pagina [Dependencies](https://github.com/SrPolvoron/Linux-server-hardening/wiki/Dependencies) para el detalle por distribucion.

## Instalacion

Clona el repositorio:

```bash
git clone https://github.com/SrPolvoron/Linux-server-hardening.git
cd Linux-server-hardening
```

Crea tu configuracion local:

```bash
cp config/local.conf.example config/local.conf
```

Editala antes del primer despliegue:

```bash
nano config/local.conf
```

No subas secretos, claves privadas ni credenciales a `config/local.conf`.

## Flujo recomendado

No ejecutes directamente un `first-deploy` sobre un servidor desconocido.

### 1. Auditoria

```bash
sudo ./hardening.sh audit
```

Muestra el estado actual sin aplicar cambios.

### 2. Plan

```bash
sudo ./hardening.sh plan
```

Muestra las acciones previstas sin modificar el sistema.

### 3. Primer despliegue

```bash
sudo ./hardening.sh first-deploy
```

Aplica los modulos definidos para el baseline utilizando un mismo deployment ID y generando snapshots de los elementos modificados.

### 4. Aplicacion modular

Tambien pueden aplicarse controles individualmente:

```bash
sudo ./hardening.sh apply ssh
sudo ./hardening.sh apply logging
sudo ./hardening.sh apply sysctl
sudo ./hardening.sh apply docker
```

## Configuracion

Los valores base se encuentran en:

```text
config/defaults.conf
```

Las personalizaciones del servidor deben realizarse preferentemente en:

```text
config/local.conf
```

Ejemplos de parametros configurables:

```bash
ADMIN_USER=jfernandez
SSH_PORT=2255
LOG_RETENTION_DAYS=180
ENABLE_FAIL2BAN=yes
ENABLE_ETCKEEPER=yes
ADD_ADMIN_TO_DOCKER_GROUP=yes
DOCKER_LOG_DRIVER=json-file
DOCKER_LOG_MAX_SIZE=100m
DOCKER_LOG_MAX_FILE=5
DOCKER_LOG_COMPRESS=true
```

Consulta [Configuration](https://github.com/SrPolvoron/Linux-server-hardening/wiki/Configuration) para todas las opciones.

## SSH

El modulo SSH aplica y valida, entre otros:

```text
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
IgnoreRhosts yes
HostbasedAuthentication no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
```

El puerto es configurable.

Antes de desactivar password authentication se comprueba que el usuario administrador dispone de una clave publica utilizable. La configuracion se valida con `sshd -t` y se inspecciona mediante `sshd -T` antes de considerar el modulo correcto.

En SELinux, los puertos SSH no estandar se registran como `ssh_port_t` cuando corresponde.

## Logging

El baseline utiliza journald persistente y limites explicitos para impedir que una politica temporal de retencion provoque consumo de disco sin control.

Configuracion de referencia:

```ini
[Journal]
Storage=persistent
Compress=yes
MaxRetentionSec=180day
SystemMaxUse=8G
SystemKeepFree=10G
SystemMaxFileSize=128M
RuntimeMaxUse=1G
```

`MaxRetentionSec=180day` es una retencion maxima temporal, no una garantia de conservar 180 dias localmente. Los limites de espacio pueden provocar rotacion anterior.

Para retencion de seguridad prolongada se recomienda centralizacion mediante Wazuh/SIEM u otra plataforma equivalente.

El modulo tambien audita `rsyslog`, `logrotate` y su timer cuando aplican.

## Auditd

Se monitorizan cambios sensibles sobre elementos como:

- usuarios y grupos;
- credenciales locales;
- sudoers;
- configuracion SSH;
- configuracion de auditd;
- configuracion systemd;
- identidad del sistema.

La rotacion de `audit.log` la gestiona auditd y no logrotate.

El proyecto evita politicas de disco lleno extremadamente destructivas de forma generica y diferencia entre retencion local y retencion centralizada.

## Sysctl

Se aplican controles como:

```text
kernel.randomize_va_space=2
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.yama.ptrace_scope=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.*.accept_source_route=0
net.ipv4.conf.*.accept_redirects=0
net.ipv4.conf.*.send_redirects=0
```

Por compatibilidad con servidores reales, el baseline no fuerza valores genericos para `ip_forward` o `rp_filter`.

## SELinux

En sistemas RHEL-like, la activacion desde un estado `Disabled` sigue un flujo conservador:

```text
Disabled
  -> instalar/verificar dependencias
  -> preparar puertos y politica necesaria
  -> Permissive
  -> autorelabel
  -> reboot
  -> revisar servicios y AVC
  -> probar Enforcing
  -> validar nuevamente
  -> persistir Enforcing
```

Nunca se genera un `audit2allow` automaticamente a partir de un AVC.

Antes de crear excepciones se comprueba si el problema se resuelve actualizando la politica SELinux o el paquete afectado.

## Fail2ban

No basta con tener el servicio `active`.

El proyecto comprueba que exista un jail funcional para SSH y selecciona la accion de bloqueo segun las capacidades reales del host:

- firewalld activo;
- nftables;
- iptables como fallback cuando corresponde.

La configuracion se valida antes de reiniciar Fail2ban.

## Docker

Docker es un modulo separado porque modificar su daemon puede afectar workloads de produccion.

Configuracion de logging de referencia:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5",
    "compress": "true"
  }
}
```

El modulo:

- preserva claves existentes de `daemon.json`;
- valida el JSON antes de aplicarlo;
- utiliza validacion del daemon cuando esta disponible;
- evita reinicios automaticos con workloads activos en modo `auto`;
- informa de contenedores que siguen utilizando configuracion anterior;
- puede detectar servicios Swarm en estado `0/N`;
- audita crecimiento potencial de logs.

Los contenedores existentes pueden necesitar recreacion para heredar nuevos defaults de logging.

## Backups y rollback

Cada deployment mantiene su propio estado de backup bajo:

```text
/etc/server-hardening/backups/
```

La version actual diferencia entre:

- archivos existentes modificados;
- archivos creados por el hardening;
- estado relevante del sistema;
- modulo que produjo el cambio;
- deployment al que pertenece.

Comandos:

```bash
sudo ./hardening.sh rollback list
sudo ./hardening.sh rollback latest
sudo ./hardening.sh rollback latest ssh
```

Antes de un rollback se crea un checkpoint del estado actual. Si la restauracion produce una configuracion invalida, el sistema intenta recuperar ese checkpoint.

El rollback es deliberadamente conservador:

- no elimina paquetes por defecto;
- no elimina usuarios automaticamente;
- no reinicia Docker de forma agresiva;
- valida configuraciones despues de restaurarlas;
- no silencia fallos criticos.

Consulta [Backup and Rollback](https://github.com/SrPolvoron/Linux-server-hardening/wiki/Backup-and-Rollback).

## Audit y Report

`audit` muestra el estado actual y las desviaciones detectadas:

```bash
sudo ./hardening.sh audit
```

`report` genera evidencia persistente del host:

```bash
sudo ./hardening.sh apply report
```

El informe incluye informacion de distribucion, SSH, MAC, tiempo, puertos, almacenamiento y otros controles disponibles, con permisos restrictivos.

## Firewall

El firewall local **no se administra por defecto**.

Esto es deliberado: muchos servidores estan protegidos por firewalls perimetrales, security groups, appliances o reglas externas que no deben ser sobreescritas por un baseline generico.

El proyecto puede detectar el estado de firewalld, nftables o UFW y utilizarlo como contexto para otros modulos, pero no reemplaza la politica de red de la infraestructura.

## ENS

Este proyecto puede servir como baseline tecnico para implementar y evidenciar determinadas medidas de seguridad, pero **no convierte un sistema en conforme con ENS por si solo**.

ENS tambien requiere medidas organizativas, gestion de riesgos, procedimientos, evidencias, control de acceso, gestion de incidentes, continuidad, auditorias y otros requisitos fuera del alcance de un script de hardening.

Consulta [ENS Considerations](https://github.com/SrPolvoron/Linux-server-hardening/wiki/ENS-Considerations).

## Estado de validacion

`v7.0.0-rc1` debe considerarse una release candidate.

La promocion a estable requiere pruebas por distribucion que cubran como minimo:

```text
audit
plan
first-deploy
segundo apply / idempotencia
reboot
health checks
rollback por modulo
rollback del deployment
```

Matriz objetivo:

- Debian 12 / 13
- Ubuntu 22.04 / 24.04 / 26.04
- AlmaLinux 9 / 10
- Rocky Linux 9 / 10
- RHEL/UBI 9 / 10

Consulta [Testing Matrix](https://github.com/SrPolvoron/Linux-server-hardening/wiki/Testing-Matrix).

## Estructura del proyecto

```text
Linux-server-hardening/
├── hardening.sh
├── README.md
├── RELEASE_NOTES.md
├── SECURITY.md
├── config/
├── lib/
├── modules/
└── tests/
```

La documentacion extensa se mantiene en la GitHub Wiki para evitar convertir el README en un manual de operaciones completo.

## Documentacion

Documentacion completa:

**https://github.com/SrPolvoron/Linux-server-hardening/wiki**

Secciones principales:

- Architecture
- Installation
- Configuration
- Supported Distributions
- Dependencies
- First Deploy
- Users and Privileges
- SSH
- Auditd
- Logging
- Sysctl and Kernel
- NTP and Chrony
- SELinux
- AppArmor
- Fail2ban
- Etckeeper
- Docker
- Locale
- Firewall
- Audit
- Report
- Backup and Rollback
- Production Safeguards
- Troubleshooting
- Testing Matrix
- ENS Considerations
- Changelog and Design Decisions

## Seguridad y contribuciones

Antes de abrir una incidencia de seguridad consulta `SECURITY.md`.

Los cambios que afecten a SSH, SELinux/AppArmor, Docker, auditd, networking o rollback deben validarse primero en staging.

No se recomienda ejecutar una nueva version directamente sobre servidores de produccion sin revisar previamente:

```bash
sudo ./hardening.sh audit
sudo ./hardening.sh plan
```

## Licencia

Añade aqui la licencia elegida para el proyecto antes de publicar una release estable.
