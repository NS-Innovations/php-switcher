# php-switcher
# SPDX-License-Identifier: MIT

PREFIX ?= /usr/local
SBINDIR ?= $(PREFIX)/sbin

.PHONY: install uninstall check test

install:
	install -D -m 755 php-switch $(DESTDIR)$(SBINDIR)/php-switch

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/php-switch

check:
	bash -n php-switch
	shellcheck php-switch tests/run.sh

test:
	tests/run.sh
