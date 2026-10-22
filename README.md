# php-switcher

Switch a live Debian or Ubuntu server from one PHP version to another — PHP-FPM, the web server,
the `php` command and every service that runs PHP — with health checks and automatic rollback.

```
sudo php-switch
```

opens a menu. Pick a version, read the plan, confirm. That's it.

The menu is plain text, line by line: numbered choices, simple prompts, and results printed in order
between clear headings. Nothing is drawn or redrawn on the screen, so it works well with screen
readers (Orca, speakup, NVDA or JAWS over SSH) and braille displays, and over any SSH connection.

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

## Install

```
git clone https://github.com/NS-Innovations/php-switcher.git
cd php-switcher
sudo make install            # installs /usr/local/sbin/php-switch
```

It is a single bash script, so copying `php-switch` anywhere on root's `PATH` works too.
`sudo make uninstall` removes it.

## Using the menu

```
sudo php-switch
```

```
php-switch 1.3.0 on Debian GNU/Linux 12 (bookworm), using packages.sury.org.
Running php-fpm: 8.2. The php command: php 8.2.
Main menu:
  1. Switch PHP version
  2. Status: installed versions and what is active
  3. Services and programs that run PHP
  4. Health check
  5. Repository and signing key
  6. Versions available to install
  7. Regenerate the ionCube loader
  8. Settings
  9. Quit
Main menu. Choose 1 to 9, or press Enter to hear the choices again:
```

Type a number and press Enter. In lists, 0 goes back. Results start with a `== Title` line and end
with `== End of Title.`, so you always know where one finishes.

| Choice | What it does |
|---|---|
| Switch PHP version | choose a version, answer a few questions, read the plan, confirm |
| Status | installed versions, which PHP-FPM is running, its pools, the `php` command |
| Services and programs that run PHP | what a switch would restart, and what it would leave alone and why |
| Health check | probe every PHP-FPM pool, plus any URLs you give |
| Repository and signing key | check only, or check and repair; add the repository if it is missing |
| Versions available to install | everything apt can install, prereleases marked |
| Regenerate the ionCube loader | reinstall the loader for a PHP version, then check the encoded files against it |
| Settings | default check URLs, lint directories, and whether to restart services |

When switching you can type the version itself (`8.4`) instead of its number. Then it asks:

- **Restart the services and supervisor programs that run PHP?** (yes by default)
- **URLs that must keep answering after the switch** — for example your login page
- **Directories to check with php -l before switching** — every `.php` file is checked with the new
  version; a file that parses today but not on the new version stops the switch before anything
  changes
- **Continue even if PHP extensions would go missing?** (no by default)

Each question shows its default in brackets; press Enter to keep it, or type `none` to clear a list.
Your answers become the defaults next time. Then the plan is printed — packages, pools and
sockets, web server files, the `php` command, and each service that will be restarted or left
alone — and nothing changes until you answer yes.

Settings are kept in `/etc/php-switch.conf`. Set `NO_COLOR=1` to turn colors off.

## Command line

Every menu function is also a command, for scripts and automation:

```
php-switch status
php-switch list
php-switch services
php-switch check [--check-url URL]
php-switch ioncube [x.y]
php-switch repo [--check]
php-switch switch <x.y|latest> [options]
php-switch version
```

`switch` options: `--yes`, `--dry-run`, `--from x.y`, `--lint DIR`, `--check-url URL`,
`--allow-prerelease`, `--allow-missing-ext`, `--allow-ioncube-mismatch`, `--no-restart`. `latest` means the newest stable
version; release candidates are only used with `--allow-prerelease`.

```
sudo php-switch switch 8.4 --dry-run
sudo php-switch switch latest --yes --check-url https://example.com/login.php --lint /var/www/app
```

## How a switch works

1. Check the PHP repository and its signing key, repairing a broken key.
2. Install the target version with the same extension packages.
3. Carry over `php.ini`, `php-fpm.conf`, pool and `conf.d` changes, systemd drop-ins and ionCube.
4. Validate: `php-fpm -t`, startup warnings, extension parity, ionCube-encoded files, optional lint.
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
- **JIT and ionCube**: ionCube installs its own opcode handlers, which JIT cannot work with. PHP
  8.4 and newer then warn at every start that JIT was disabled. When that happens, the switch sets
  `opcache.jit = disable` in `conf.d/99-php-switch-jit.ini`, which is what PHP was doing anyway.
- **Extensions compiled into PHP itself** come and go with the version (for example `random` in 8.2,
  `opcache`, `lexbor` and `uri` in 8.5) and are not reported as missing.
- **ionCube loaders** are downloaded from ioncube.com when the server already uses ionCube. Set
  `IONCUBE_DIR` to a directory of loaders to use local copies instead.
- **ionCube loader on FusionPBX servers**: when `/usr/src/fusionpbx-install.sh` (or
  `$FUSIONPBX_INSTALL_DIR`) is present, the loader is generated with its `resources/ioncube.sh`,
  as the FusionPBX installer does, for every version that script has a section for; otherwise it
  is downloaded from ioncube.com. The script runs from a scratch copy of its directory with
  `php_version` set to the target, so the install repository is not modified. Its php-fpm restart
  is skipped, and the loader file is replaced rather than overwritten in place, because
  overwriting a loader that a running php-fpm has loaded crashes it. `php-switch ioncube [x.y]`
  (or the menu) regenerates the loader on demand, reloads php-fpm gracefully only if the loader
  changed, and checks the encoded files against it.
- **ionCube-encoded files** only load on the PHP versions their encoder supports: files encoded for
  PHP 8.1 run only on 8.1, files from the PHP 8.2–8.4 encoders run on 8.2 to 8.5, and files for
  PHP 7.x run up to 7.4. Before switching, every `.php` file under the web server's document roots
  (and any lint directories) is test-loaded with the new version — `php -l` compiles it through the
  loader without running it. All files are checked, because an encoded file cannot always be
  recognised by its contents; for a FusionPBX install this takes about 25 seconds. If a file that works today would stop working, the switch stops before
  the live server changes and names the file and the versions it does load on. The fix is a copy
  encoded for the new version from the file's vendor; `--allow-ioncube-mismatch` switches anyway.
  The health check reports encoded files the running version cannot load.
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

The menu tests type their answers on standard input, and check that the menu never prints terminal
control sequences that would confuse a screen reader.

## Contributing

Issues and pull requests are welcome. Please keep `shellcheck` clean, follow the existing style
(tabs; a lowercase comment above each indented block), and run `sudo tests/run.sh` on a Debian or
Ubuntu machine before sending a change.

## License

MIT — see [LICENSE](LICENSE).

php-switcher is an independent project. It is not affiliated with the PHP project, Debian, Ubuntu,
or the maintainers of packages.sury.org and ppa:ondrej/php — whose packages make running several
PHP versions side by side possible in the first place.
