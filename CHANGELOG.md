# Changelog

## 1.1.0 — 2026-10-21

- The menu is now line-based: numbered choices, plain prompts, and results between headings, with
  nothing drawn or redrawn on screen. It works with screen readers and braille displays, and no
  longer needs whiptail. You can type a version (`8.4`) instead of its number. `NO_COLOR` is honoured.
- Fixed: switching to PHP 8.4 or newer stopped with "php reports startup problems" when ionCube was
  loaded. PHP 8.4 reserves a JIT buffer by default, and JIT cannot run alongside ionCube, so PHP
  warned at every start. The switch now sets `opcache.jit = disable` for the new version in that
  case.
- Actions run from the menu no longer read from the keyboard, so typing ahead cannot answer a
  question meant for later.

## 1.0.0 — 2026-10-21

First public release.

- Interactive menu (whiptail): switch, status, services, health check, repository and key,
  available versions, settings. Every function also works as a command.
- Live PHP switching on Debian and Ubuntu with packages.sury.org / ppa:ondrej/php: parallel
  PHP-FPM start, FastCGI pool probes, web server rewrite and graceful reload (nginx, Apache,
  Caddy, lighttpd), `php` alternatives, automatic rollback.
- Repository signing key checks and repair: missing, empty, expired, revoked, wrong key,
  armored-in-.gpg, and inline deb822 keys. Adds the repository when it is missing.
- Configuration carry-over: php.ini changes against the packaged default, php-fpm.conf and pools,
  conf.d files, systemd drop-ins, ionCube.
- Restarts the systemd services and supervisor programs that run PHP through the `php` command;
  leaves version-pinned processes alone.
- Validation before anything changes: php-fpm -t, startup warnings (rejected php.ini settings are
  disabled), extension parity, optional lint that fails only on new parse errors.
