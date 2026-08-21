# v7.0.0-rc1

v7 is a redesign based on production validation of the previous shell implementation.

## Major changes

- Distribution-family package-manager detection; fixes AlmaLinux choosing APT merely because `apt-get` exists.
- Required/optional dependency resolver with explicit repository policy.
- Deployment-level state manifest and secure backups.
- Automatic per-module recovery when `apply` fails.
- Transactional manual rollback with targeted pre-rollback checkpoint and automatic recovery on failed validation.
- SSH lockout guards, explicit first-priority managed include, effective-value validation and SELinux port preparation.
- Persistent/bounded journald plus managed rsyslog rotation.
- Modern auditd rules and immutable-rule handling.
- Safe SELinux transition and timestamped Enforcing validation; no automatic `audit2allow`.
- AppArmor branch for Debian/Ubuntu.
- Functional Fail2ban jail with firewall backend selection.
- Dedicated Docker logging module with JSON merge, daemon validation and workload-aware restart behavior.
- Locale validation/installation.
- GitHub Wiki package and GitHub Actions smoke tests.

## Validation status

The test suite currently validates syntax, the historical package-manager regression, manifest restoration, transaction recovery and automatic failed-module rollback. The code also has read-only smoke plans suitable for CI containers.

Full production support still requires staging VMs for each target distribution/version, especially for systemd, SSH, auditd, SELinux/AppArmor, reboot/relabel and real rollback behavior. This is intentionally an `rc1`, not a claim that every target has already been field-tested.
