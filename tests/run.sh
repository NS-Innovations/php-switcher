#!/usr/bin/env bash
#
# run.sh - tests for php-switch
#
#   sudo tests/run.sh            syntax, shellcheck, and every menu flow that changes nothing
#   sudo tests/run.sh --switch   also switches PHP through the menu and back again; this changes the
#                                machine, so run it only on a disposable VM, container or CI runner
#
# The menu tests drive php-switch through tests/fake-whiptail and need root on Debian or Ubuntu
# with systemd, like php-switch itself.
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
	T=$'\t'
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	export FAKE_WHIPTAIL_LOG=$tmp/log
	export FAKE_WHIPTAIL_QUEUE=$tmp/queue
	export PHP_SWITCH_WHIPTAIL=$PWD/tests/fake-whiptail
	export PHP_SWITCH_CONF=$tmp/php-switch.conf

#result helpers
	pass() { echo "  ok   $*"; passed=$((passed + 1)); }
	fail() { echo "  FAIL $*"; failed=$((failed + 1)); }
	skip() { echo "  skip $*"; skipped=$((skipped + 1)); }

#run the menu with queued answers ("<exit code><TAB><answer>" per box); stdin answers "press Enter"
	menu() {
		: > "$FAKE_WHIPTAIL_LOG"
		printf '%s\n' "$@" > "$FAKE_WHIPTAIL_QUEUE"
		printf '\n\n\n\n' | "$script" menu > "$tmp/out" 2>&1
		menu_rc=$?
	}

#the log of the last menu run contains a fixed string
	expect() {
		if grep -F -- "$2" "$FAKE_WHIPTAIL_LOG" >/dev/null; then
			pass "$1"
		else
			fail "$1 (expected: $2)"
			sed 's/^/         /' "$FAKE_WHIPTAIL_LOG" | tail -20
		fi
	}

#the last menu run used every queued answer and exited cleanly
	expect_clean() {
		if grep -F '!!! queue empty' "$FAKE_WHIPTAIL_LOG" >/dev/null; then
			fail "$1: the menu asked for more input than expected"
			sed 's/^/         /' "$FAKE_WHIPTAIL_LOG" | tail -20
		elif [ -s "$FAKE_WHIPTAIL_QUEUE" ]; then
			fail "$1: answers left unused: $(tr '\n' ' ' < "$FAKE_WHIPTAIL_QUEUE")"
		elif [ "$menu_rc" -ne 0 ]; then
			fail "$1: menu exited $menu_rc"
			tail -20 "$tmp/out" | sed 's/^/         /'
		else
			pass "$1: menu exited cleanly"
		fi
	}

#static checks
	echo "static"
	if bash -n "$script"; then pass "bash -n"; else fail "bash -n"; fi
	if command -v shellcheck >/dev/null 2>&1; then
		if shellcheck "$script" tests/run.sh tests/fake-whiptail; then pass "shellcheck"; else fail "shellcheck"; fi
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

#read-only menu flows
	echo "menu"
	cli_before=$(readlink -f /usr/bin/php 2>/dev/null || echo none)

	menu "0${T}quit"
	expect "main menu" "=== menu: php-switch"
	expect_clean "quit"

	menu "1${T}"
	expect_clean "cancel leaves the menu"

	menu "0${T}status" "0${T}quit"
	expect "status screen" "=== textbox: Status"
	expect "status content" "installed:"
	expect_clean "status"

	menu "0${T}services" "0${T}quit"
	expect "services screen" "=== textbox: Services running PHP"
	expect "services content" "default cli:"
	expect_clean "services"

	menu "0${T}versions" "0${T}quit"
	expect "versions screen" "=== textbox: Versions available to install"
	expect_clean "versions"

	menu "0${T}check" "0${T}" "0${T}quit"
	expect "health check screen" "=== textbox: Health check"
	expect_clean "health check"

	menu "0${T}repo" "0${T}check" "0${T}quit"
	expect "repository check screen" "=== textbox: Repository check"
	expect_clean "repository check"

	menu "0${T}settings" "0${T}http://127.0.0.1/" "0${T}/srv/www" "1${T}" "0${T}quit"
	if grep -Fx 'check_urls="http://127.0.0.1/"' "$PHP_SWITCH_CONF" >/dev/null \
		&& grep -Fx 'lint_dirs="/srv/www"' "$PHP_SWITCH_CONF" >/dev/null \
		&& grep -Fx 'restart_dependents="off"' "$PHP_SWITCH_CONF" >/dev/null; then
		pass "settings saved"
	else
		fail "settings saved"
		sed 's/^/         /' "$PHP_SWITCH_CONF"
	fi
	expect_clean "settings"
	rm -f "$PHP_SWITCH_CONF"

#pick a version to switch to: not the active one, not a prerelease
	active=$("$script" status | awk '/running,/ {print $1; exit}')
	[ -n "$active" ] || active=$(readlink -f /usr/bin/php 2>/dev/null | sed -n 's#^/usr/bin/php##p')
	target=$("$script" list | awk -v a="$active" '$1 != a && !/prerelease/ && $1 ~ /^[0-9]+\.[0-9]+$/ {v = $1} END {print v}')
	running_count=$("$script" status | grep -c 'running,' || true)
	repo_prompt=()
	if ! grep -rlE '^[^#]*(packages\.sury\.org|ppa\.launchpad(content)?\.net/ondrej/)' /etc/apt/sources.list /etc/apt/sources.list.d/ >/dev/null 2>&1; then
		repo_prompt=("1${T}")
	fi

	if [ -z "$target" ]; then
		skip "switch flow: apt offers no second php version"
	elif [ "$running_count" -gt 1 ]; then
		skip "switch flow: several php-fpm are running"
	else
		menu "0${T}switch" "${repo_prompt[@]}" "0${T}$target" "0${T}restart" "0${T}" "1${T}" "0${T}quit"
		expect "switch: version list" "=== radiolist: Switch PHP version"
		expect "switch: plan shown" "=== textbox: Plan"
		expect "switch: plan names the target" "-> php $target"
		expect "switch: asks before applying" "=== yesno: Apply"
		expect_clean "switch declined"
		if [ "$(readlink -f /usr/bin/php 2>/dev/null || echo none)" = "$cli_before" ]; then
			pass "switch declined: nothing changed"
		else
			fail "switch declined: /usr/bin/php changed"
		fi
	fi

#a real switch through the menu and back
	if $do_switch && [ -n "$target" ] && [ "$running_count" -le 1 ]; then
		echo "switch (changes this machine)"
		for version in "$target" "$active"; do
			menu "0${T}switch" "0${T}$version" "0${T}restart" "0${T}" "0${T}" "0${T}quit"
			expect "switch to $version: plan" "=== textbox: Plan"
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
