# Contributing to Vault Lab Helper

Thanks for your interest in contributing! This project is a **development and educational tool** for running a local HashiCorp Vault + Consul lab. It is **not production-ready** software. Contributions are welcome, but please keep the scope aligned with the project’s goals: simplicity, clarity, and usability for lab/test environments.

---

## How to Contribute

### 1. Reporting Issues
- Use the GitHub Issues tab.
- Provide clear reproduction steps, including:
  - OS/distribution and version
  - Bash version
  - Vault/Consul versions in use
  - Full command you ran and log output
- Avoid vague bug reports like “it doesn’t work.” Those will be closed.

### 2. Suggesting Enhancements
Enhancements are welcome, but keep in mind:
- Focus on **improving developer experience** (clearer logs, safer defaults, less duplication).
- Avoid adding features that turn the script into a full deployment tool (e.g., TLS cert management, clustering, production hardening). That’s out of scope.

### 3. Submitting Changes
- Fork the repo and create a feature branch (`git checkout -b feature/my-change`).
- Make atomic commits with clear messages.
  - Follow [Conventional Commits](https://www.conventionalcommits.org/) if possible (`fix: …`, `feat: …`, `docs: …`, `refactor: …`).
- Submit a pull request (PR) with:
  - A description of what you changed
  - Why the change is useful
  - Any testing you performed

### 4. Coding Style
- Stick to **POSIX-compliant Bash** features where possible.
- Prefer small functions over inline repeated logic.
- Use the provided `log_info`, `log_warn`, `log_error`, `safe_run`, and `warn_run` helpers for all output and error handling.
- All new commands that can fail should go through `safe_run` or `warn_run`.

### 5. Documentation
- Update `display_help` if you add or change commands or options.
- Update `README.md` if your change affects usage.
- Use comments sparingly but clearly inside the script.

### 6. Testing
This project doesn’t have an automated test suite (yet). Please:
- Run `./dev.sh reset` and verify the script can complete a clean start on your machine.
- Test both `file` and `consul` backends if your change touches storage logic.
- Provide example logs in the PR if possible.

---

## Code of Conduct
Don’t be a jerk. Respectful discussion only. This is a community-driven learning project.

---

## License
By contributing, you agree that your code will be released under the same license as this project (MIT unless otherwise noted).
