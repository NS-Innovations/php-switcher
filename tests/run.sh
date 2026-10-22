#!/usr/bin/env bash
#
# run.sh - tests for php-switch
#
#   sudo tests/run.sh            syntax, shellcheck, and every menu flow that changes nothing
#   sudo tests/run.sh --switch   also switches PHP through the menu and back again; this changes the
#                                machine, so run it only on a disposable VM, container or CI runner
#
# The menu tests type their answers on standard input and need root on Debian or Ubuntu with
# systemd, like php-switch itself. Every menu run is also checked for terminal control sequences,
# which would get in the way of screen readers.
#
# SPDX-License-Identifier: MIT

set -o nounset -o pipefail

#set defaults
	cd "$(dirname "$0")/.." || exit 1
	script=$PWD/php-switch
	do_switch=false
	if [ "${1:-}" = --switch ]; then do_switch=true; fi
	passed=0
	failed=0
	skipped=0
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	export PHP_SWITCH_CONF=$tmp/php-switch.conf

#result helpers
	pass() { echo "  ok   $*"; passed=$((passed + 1)); }
	fail() { echo "  FAIL $*"; failed=$((failed + 1)); }
	skip() { echo "  skip $*"; skipped=$((skipped + 1)); }

#run the menu, answering each prompt with the next argument
	menu() {
		printf '%s\n' "$@" | "$script" menu > "$tmp/out" 2>&1
		menu_rc=$?
	}

#the output of the last menu run contains a fixed string
	expect() {
		if grep -F -- "$2" "$tmp/out" >/dev/null; then
			pass "$1"
		else
			fail "$1 (expected: $2)"
			tail -20 "$tmp/out" | sed 's/^/         /'
		fi
	}

#the last menu run ended at the main menu with Goodbye, exit 0, and printed no control sequences
	expect_clean() {
		if [ "$menu_rc" -ne 0 ]; then
			fail "$1: menu exited $menu_rc"
			tail -20 "$tmp/out" | sed 's/^/         /'
		elif [ "$(tail -n 1 "$tmp/out")" != "Goodbye." ]; then
			fail "$1: did not end with Goodbye"
			tail -20 "$tmp/out" | sed 's/^/         /'
		elif LC_ALL=C grep -q $'[\x1b\r\x07\x08]' "$tmp/out"; then
			fail "$1: output contains terminal control characters"
		else
			pass "$1"
		fi
	}

#static checks
	echo "static"
	if bash -n "$script"; then pass "bash -n"; else fail "bash -n"; fi
	if command -v shellcheck >/dev/null 2>&1; then
		if shellcheck "$script" tests/run.sh; then pass "shellcheck"; else fail "shellcheck"; fi
	else
		skip "shellcheck is not installed"
	fi
	if "$script" --help | grep -F 'SPDX-License-Identifier: MIT' >/dev/null; then pass "--help prints the header"; else fail "--help"; fi
	if "$script" version | grep -E '^php-switch [0-9]+\.[0-9]+\.[0-9]+$' >/dev/null; then pass "version"; else fail "version"; fi

	if [ "$(id -u)" != 0 ]; then
		skip "menu tests need root"
		echo
		echo "$passed passed, $failed failed, $skipped skipped"
		[ "$failed" -eq 0 ]
		exit
	fi

#read-only menu flows; main menu: 1 switch, 2 status, 3 services, 4 check, 5 repo, 6 versions,
#7 ionCube loader, 8 settings, 9 quit
	echo "menu"
	cli_before=$(readlink -f /usr/bin/php 2>/dev/null || echo none)
	has_repo=true
	if ! grep -rlE '^[^#]*(packages\.sury\.org|ppa\.launchpad(content)?\.net/ondrej/)' /etc/apt/sources.list /etc/apt/sources.list.d/ >/dev/null 2>&1; then
		has_repo=false
	fi

	menu 9
	expect "main menu lists its choices" "  1. Switch PHP version"
	expect "main menu states what is running" "Running php-fpm:"
	expect_clean "quit with 8"

	menu 0
	expect_clean "quit with 0"

	menu
	expect_clean "end of input quits"

	menu 99 9
	expect "an unknown choice is named" "99 is not a choice."
	expect_clean "unknown choice"

	menu "" 9
	expect "Enter lists the choices again" "  9. Quit"
	expect_clean "Enter repeats the menu"

	menu 2 9
	expect "status heading" "== Status"
	expect "status content" "installed:"
	expect "status end heading" "== End of Status."
	expect_clean "status"

	menu 3 9
	expect "services heading" "== Services and programs that run PHP"
	expect "services content" "default cli:"
	expect_clean "services"

	menu 6 9
	expect "versions heading" "== Versions available to install"
	expect_clean "versions"

	menu 7 0 9
	expect "ionCube loader screen" "The loader is "
	expect_clean "ionCube loader: 0 goes back"

	menu 4 none 9
	expect "health check heading" "== Health check"
	expect_clean "health check"

	if $has_repo; then menu 5 1 8; else menu 5 2 8; fi
	expect "repository check heading" "== Repository check"
	expect_clean "repository check"

	menu 8 http://127.0.0.1/ /srv/www no 9
	if grep -Fx 'check_urls="http://127.0.0.1/"' "$PHP_SWITCH_CONF" >/dev/null \
		&& grep -Fx 'lint_dirs="/srv/www"' "$PHP_SWITCH_CONF" >/dev/null \
		&& grep -Fx 'restart_dependents="off"' "$PHP_SWITCH_CONF" >/dev/null; then
		pass "settings saved"
	else
		fail "settings saved"
		sed 's/^/         /' "$PHP_SWITCH_CONF"
	fi
	expect_clean "settings"
	menu 8 none none yes 9
	if grep -Fx 'check_urls=""' "$PHP_SWITCH_CONF" >/dev/null && grep -Fx 'restart_dependents="on"' "$PHP_SWITCH_CONF" >/dev/null; then
		pass "settings: none clears a list"
	else
		fail "settings: none clears a list"
	fi
	rm -f "$PHP_SWITCH_CONF"

#pick a version to switch to: not the active one, not a prerelease
	active=$("$script" status | awk '/running,/ {print $1; exit}')
	[ -n "$active" ] || active=$(readlink -f /usr/bin/php 2>/dev/null | sed -n 's#^/usr/bin/php##p')
	target=$("$script" list | awk -v a="$active" '$1 != a && !/prerelease/ && $1 ~ /^[0-9]+\.[0-9]+$/ {v = $1} END {print v}')
	running_count=$("$script" status | grep -c 'running,' || true)
	repo_answer=()
	if ! $has_repo; then repo_answer=(no); fi

	if [ -z "$target" ]; then
		skip "switch flow: apt offers no second php version"
	elif [ "$running_count" -gt 1 ]; then
		skip "switch flow: several php-fpm are running"
	else
		#switch, [repository], version, restart, urls, lint, missing extensions, apply, quit
		menu 1 "${repo_answer[@]}" "$target" yes none none no no 9
		expect "switch: version list" "Versions apt can install:"
		expect "switch: plan heading" "== Plan"
		expect "switch: plan names the target" "-> php $target"
		expect "switch: declined" "Nothing was changed."
		expect_clean "switch declined"
		if [ "$(readlink -f /usr/bin/php 2>/dev/null || echo none)" = "$cli_before" ]; then
			pass "switch declined: nothing changed"
		else
			fail "switch declined: /usr/bin/php changed"
		fi

		menu 1 "${repo_answer[@]}" 0 9
		expect_clean "switch: 0 goes back"
	fi

#a real switch through the menu and back
	if $do_switch && [ -n "$target" ] && [ "$running_count" -le 1 ]; then
		echo "switch (changes this machine)"
		for version in "$target" "$active"; do
			menu 1 "$version" yes none none no yes 9
			expect "switch to $version: plan" "== Plan"
			expect "switch to $version: finished" "== End of Switching to php $version."
			expect_clean "switch to $version"
			if grep -F "switched php" "$tmp/out" >/dev/null && [ "$(readlink -f /usr/bin/php)" = "/usr/bin/php$version" ]; then
				pass "switch to $version: /usr/bin/php -> php$version"
			else
				fail "switch to $version"
				tail -25 "$tmp/out" | sed 's/^/         /'
			fi
		done
	elif $do_switch; then
		skip "real switch: no suitable second version"
	fi

	echo
	echo "$passed passed, $failed failed, $skipped skipped"
	[ "$failed" -eq 0 ]
