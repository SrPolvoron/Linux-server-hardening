# Security model

This project changes privileged operating-system configuration. Treat every release as infrastructure code.

- Review `audit` and `plan` before `apply`.
- Validate a new release in staging for the exact OS major/minor and workload profile.
- Keep remote console/KVM access for SSH and MAC changes.
- Never commit `config/local.conf` if it is extended with secrets.
- Never publish `/etc/.git` created by Etckeeper.
- Backups under `/etc/server-hardening/backups` are mode 0700 because they can contain sensitive configuration.
- Local SELinux `audit2allow` modules are never generated automatically.
- Docker daemon changes are validated and are not automatically restarted with active containers by default.

Report security bugs privately to the repository maintainers rather than including host-specific secrets or logs in a public issue.
