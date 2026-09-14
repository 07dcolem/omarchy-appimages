# AppImage integration for Omarchy.
#
# Nothing here writes to /usr/share/omarchy: that tree is owned by the omarchy
# package and is overwritten by `omarchy update`.

PREFIX    ?= $(HOME)/.local
BINDIR    ?= $(PREFIX)/bin
MENU_FILE ?= $(HOME)/.config/omarchy/extensions/omarchy-menu.jsonc

# -bn keeps binary operators at the start of a continuation line, which is how
# Omarchy's own scripts are written. Upstream is hand-formatted rather than
# shfmt-formatted, so this matches their idiom without claiming to reproduce it.
SHFMT_FLAGS := -i 2 -bn

SCRIPTS := $(wildcard bin/omarchy-*)
NAMES   := $(notdir $(SCRIPTS))

.PHONY: help lint format test install uninstall

help:
	@echo "Targets:"
	@echo "  lint       shellcheck + shfmt -d over bin/ and menu/"
	@echo "  format     shfmt -w $(SHFMT_FLAGS) (Omarchy house style)"
	@echo "  test       run the bats suite"
	@echo "  install    symlink the scripts into $(BINDIR) and add the menu rows"
	@echo "  uninstall  reverse install"
	@echo
	@echo "Variables: PREFIX, BINDIR, MENU_FILE, NO_MENU=1"

# Each target fails loudly when its tool is missing rather than reporting a
# false pass.
lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck missing: omarchy pkg add shellcheck" >&2; exit 1; }
	@command -v shfmt >/dev/null || { echo "shfmt missing: omarchy pkg add shfmt" >&2; exit 1; }
	shellcheck $(SCRIPTS) menu/omarchy-appimage-menu
	shfmt -d $(SHFMT_FLAGS) $(SCRIPTS) menu/omarchy-appimage-menu

format:
	@command -v shfmt >/dev/null || { echo "shfmt missing: omarchy pkg add shfmt" >&2; exit 1; }
	shfmt -w $(SHFMT_FLAGS) $(SCRIPTS) menu/omarchy-appimage-menu

test:
	@command -v bats >/dev/null || { echo "bats missing: omarchy pkg add bats" >&2; exit 1; }
	@command -v cc >/dev/null || { echo "cc missing: fixtures are compiled ELF stubs" >&2; exit 1; }
	bats tests/

install:
	@mkdir -p "$(BINDIR)"
	@for s in $(NAMES); do \
	  ln -sf "$(CURDIR)/bin/$$s" "$(BINDIR)/$$s"; \
	  echo "linked $(BINDIR)/$$s"; \
	done
ifndef NO_MENU
	@./menu/omarchy-appimage-menu add "$(MENU_FILE)"
endif

uninstall:
	@for s in $(NAMES); do \
	  rm -f "$(BINDIR)/$$s"; \
	  echo "removed $(BINDIR)/$$s"; \
	done
ifndef NO_MENU
	@./menu/omarchy-appimage-menu remove "$(MENU_FILE)"
endif
