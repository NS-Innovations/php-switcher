# php-switcher

Switch a live Debian or Ubuntu server from one PHP version to another — PHP-FPM, the web server,
the `php` command and every service that runs PHP — with health checks and automatic rollback.

```
sudo php-switch
```

opens a menu. Pick a version, look at the plan, confirm. That's it.

## What it does

- **Installs the target version** from [packages.sury.org](https://packages.sury.org/php/) (Debian)
  or [ppa:ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php) (Ubuntu), with the same
  set of extension packages you have now. Adds the repository if it is missing.
- **Repairs the repository signing key** when it is missing, empty, expired, revoked, the wrong key,
  ASCII-armored in a `.gpg` file, or inlined in a deb822 `.sources` file — then proves the fix by
  refreshing that repository.
- **Carries your configuration over**: `php.ini` changes (compared against the packaged default, so
  only what you changed moves), `php-fpm.conf` and pool settings, extra `conf.d` files, systemd
  drop-ins for the PHP-FPM unit, and the ionCube loader if you use it.
- **Switches with no downtime**: the new PHP-FPM starts next to the old one, every pool is probed
  over FastCGI, and only then is the web server pointed at the new sockets (config test first,
  then a graceful reload). nginx and Apache are tested; Caddy and lighttpd configs are handled the
  same way but have not been tested yet.
- **Switches the `php` command** (`/usr/bin/php` and the other PHP alternatives).
- **Restarts what runs PHP**: it finds running PHP processes and restarts the systemd services and
  supervisor programs they belong to. Processes started with a specific version
  (`/usr/bin/php8.2`, `#!/usr/bin/php8.2`) are left alone and reported.
- **Checks and rolls back**: if a pool, a check URL or a restarted service fails, the web server
  config, PHP-FPM, the `php` command and the services all go back to how they were.

Old versions stay installed (stopped and disabled), so switching back takes seconds.

## Requirements

- Debian or Ubuntu with systemd. Tested on Debian 12 and Ubuntu 24.04. Derivatives that identify
  as Debian or Ubuntu in `/etc/os-release` (Mint, Pop!\_OS, Raspberry Pi OS, …) are accepted but
  have not been tested.
- bash 4 or newer, root
- `whiptail` for the menu (installed by default on Debian and Ubuntu; installed on first use if not)

## Install

```
git clone <repository url> php-switcher
cd php-switcher
sudo make install            # installs /usr/local/sbin/php-switch
```

It is a single bash script, so copying `php-switch` anywhere on root's `PATH` works too.
`sudo make uninstall` removes it.

## Using the menu

```
sudo php-switch
```

| Menu item | What it does |
|---|---|
| Switch PHP version | choose a version, choose options, read the plan, confirm |
| Status | installed versions, which PHP-FPM is running, its pools, the `php` command |
| Services and programs running PHP | what a switch would restart, and what it would leave alone and why |
| Health check | probe every PHP-FPM pool, plus any URLs you give |
| Repository and signing key | check only, or check and repair; add the repository if it is missing |
| Versions available to install | everything apt can install, prereleases marked |
| Settings | default check URLs, lint directories, and whether to restart services |

Before switching, the menu asks for:

- **Restart services and supervisor programs that run PHP** (on by default)
- **PHP-lint a code directory first** — every `.php` file is checked with the new version; a file
  that parses today but not on the new version stops the switch before anything changes
- **Continue even if PHP extensions would go missing** (off by default)
- **Check URLs** — pages that must keep answering after the switch, for example your login page

The plan shows exactly what will happen: packages, pools and sockets, web server files, the `php`
command, and each service that will be restarted or left alone. Nothing changes until you confirm.

Settings are kept in `/etc/php-switch.conf`.

## Command line

Every menu function is also a command, for scripts and automation:

```
php-switch status
php-switch list
php-switch services
php-switch check [--check-url URL]
php-switch repo [--check]
php-switch switch <x.y|latest> [options]
php-switch version
```

`switch` options: `--yes`, `--dry-run`, `--from x.y`, `--lint DIR`, `--check-url URL`,
`--allow-prerelease`, `--allow-missing-ext`, `--no-restart`. `latest` means the newest stable
version; release candidates are only used with `--allow-prerelease`.

```
sudo php-switch switch 8.4 --dry-run
sudo php-switch switch latest --yes --check-url https://example.com/login.php --lint /var/www/app
```

## How a switch works

1. Check the PHP repository and its signing key, repairing a broken key.
2. Install the target version with the same extension packages.
3. Carry over `php.ini`, `php-fpm.conf`, pool and `conf.d` changes, systemd drop-ins and ionCube.
4. Validate: `php-fpm -t`, startup warnings, extension parity, optional lint.
5. Start the new PHP-FPM beside the old one and probe each pool over FastCGI.
6. Point the web server at the new sockets, test its config, reload it.
7. Switch the `php` command.
8. Restart the services and supervisor programs that run PHP through the `php` command.
9. Stop the old PHP-FPM, then run the health checks.

Steps 1–4 change nothing that serves traffic. A failure from step 5 on rolls everything back.

## Good to know

- **Sockets without a version in the path** (for example a pool listening on `127.0.0.1:9000`)
  cannot run twice, so the old PHP-FPM is stopped just before the new one starts. Expect a fraction
  of a second of errors. The plan says when this will happen.
- **Apache with mod_php** is switched with `a2dismod` / `a2enmod` and a graceful restart.
- **Settings the new version rejects** (removed or deprecated `php.ini` directives) are commented
  out in the new `php.ini`, with a note, instead of being carried over.
- **Extensions compiled into PHP itself** come and go with the version (for example `random` in 8.2,
  `opcache`, `lexbor` and `uri` in 8.5) and are not reported as missing.
- **ionCube loaders** are downloaded from ioncube.com when the server already uses ionCube. Set
  `IONCUBE_DIR` to a directory of loaders to use local copies instead.
- **Backups** of every file a switch changes are kept in `/var/backups/php-switch/<timestamp>/`.

## Files it touches

| Path | Why |
|---|---|
| `/etc/apt/sources.list.d/php-sury.list`, `php-ondrej.list` | only when adding the repository |
| `/etc/apt/keyrings/php-*.gpg` (or the keyring your source names) | only when repairing a key |
| `/etc/php/<version>/` | configuration carried over to the new version |
| `/etc/systemd/system/php<version>-fpm.service.d/` | drop-ins copied from the old version |
| web server config files that name the old socket | rewritten to the new socket |
| `/etc/php-switch.conf` | menu settings |
| `/var/backups/php-switch/` | backups |

## Tests

```
sudo tests/run.sh            # syntax, shellcheck, and every menu flow that changes nothing
sudo tests/run.sh --switch   # also switches through the menu and back: disposable machines only
```

The menu tests run `php-switch` against `tests/fake-whiptail`, which answers each dialog from a
script and records what was shown.

## Contributing

Issues and pull requests are welcome. Please keep `shellcheck` clean, follow the existing style
(tabs; a lowercase comment above each indented block), and run `sudo tests/run.sh` on a Debian or
Ubuntu machine before sending a change.

## License

MIT — see [LICENSE](LICENSE).

php-switcher is an independent project. It is not affiliated with the PHP project, Debian, Ubuntu,
or the maintainers of packages.sury.org and ppa:ondrej/php — whose packages make running several
PHP versions side by side possible in the first place.
