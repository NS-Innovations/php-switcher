# Changelog

## 1.3.0 — 2026-10-21

- FusionPBX servers: when `/usr/src/fusionpbx-install.sh` is present (or `FUSIONPBX_INSTALL_DIR`
  points at it), the ionCube loader is generated with its `resources/ioncube.sh`, the same way the
  FusionPBX installer does it. Versions the script has no section for (such as 8.5) fall back to
  the download from ioncube.com. The script runs from a scratch copy so the install repository is
  left untouched, its php-fpm restart is skipped, and its `cp` replaces the loader file instead of
  overwriting it in place (overwriting a loaded loader crashed php-fpm in testing).
- New `php-switch ioncube [x.y]` command and menu item: regenerate the loader for a version, reload
  php-fpm gracefully only when the loader or its settings changed, then check the encoded files.

## 1.2.0 — 2026-10-21

- New check for ionCube-encoded files. A file encoded for PHP 8.1 runs only on 8.1, so switching
  from 8.1 to 8.4 left such files failing with "Only files produced by either the PHP 8.2 or 8.3 or
  8.4 ionCube Encoders can run on PHP 8.4 or 8.5". Before switching, every encoded file under the
  document roots and lint directories is now test-loaded with the new version (`php -l`, which
  compiles through the loader without running the file). The switch stops before the live server
  changes if a file would stop loading, and names the versions it does load on.
  `--allow-ioncube-mismatch` overrides. The switch also stops if the new version has no ionCube
  loader while encoded files are present.
- The health check (menu and `php-switch check`) reports encoded files the running version cannot
  load, with the versions they do load on.

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
