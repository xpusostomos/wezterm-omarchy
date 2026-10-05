# wezterm-omarchy -- make WezTerm follow the active Omarchy colour scheme.
#
#   make install          ask first, then install everything
#   make install MODE=local
#   make install MODE=global
#   make help             list every target
#
# Every feature also has its own target, so you can install just the parts you
# want. Local installs need no root and survive Omarchy updates; global installs
# configure the whole machine and do.

SHELL := /bin/bash

REPO := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SCRIPTS := $(REPO)/scripts

# Where Omarchy lives. Note this is the package-owned system tree here, which is
# why the local install is the recommended one. Override for testing:
#   make install-all-global PREFIX=/tmp/tree
PREFIX ?= /usr/share/omarchy
SKEL ?= /etc/skel
ETC ?= /etc

# Passed through to the scripts.
export REPO PREFIX SKEL ETC
export DRY_RUN FORCE GLOBAL_SKIP_USER UNINSTALL_GIST_LEFTOVERS FORCE_GRACE

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

.PHONY: install
ifeq ($(MODE),local)
install: install-all-local
else ifeq ($(MODE),global)
install: install-all-global
else
install: ## Install everything (asks local or global)
	@if [[ ! -t 0 ]]; then \
		echo "no terminal to prompt on; use 'make install MODE=local' or MODE=global" >&2; \
		exit 1; \
	fi; \
	printf '\n  Where should WezTerm theming be installed?\n\n'; \
	printf '    1) this user only  -- no root, survives Omarchy updates (recommended)\n'; \
	printf '    2) whole system    -- needs root, configures every account\n\n'; \
	read -rp '  Choice [1/2]: ' answer; \
	case "$$answer" in \
		1|local|L) echo; $(MAKE) --no-print-directory install-all-local ;; \
		2|global|G) echo; $(MAKE) --no-print-directory install-all-global ;; \
		*) echo "unrecognised choice: $$answer" >&2; exit 1 ;; \
	esac
endif

.PHONY: install-all-local install-all-global
install-all-local: ## Install every feature for this user (no root)
	@$(SCRIPTS)/install-all.sh --local

install-all-global: ## Install every feature system-wide (needs root)
	@$(SCRIPTS)/install-all.sh --global

# ---------------------------------------------------------------------------
# individual features
# ---------------------------------------------------------------------------

.PHONY: install-theme-local install-theme-global
install-theme-local: ## The config + theme template + reload hook, for this user
	@$(SCRIPTS)/install-theme.sh --local

install-theme-global: ## Theme template for every user on the machine
	@$(SCRIPTS)/install-theme.sh --global

.PHONY: install-font-local install-font-global
install-font-local: ## Font config + hook, following `omarchy font set`
	@$(SCRIPTS)/install-font.sh --local

install-font-global: ## Font support system-wide + seed new accounts
	@$(SCRIPTS)/install-font.sh --global

.PHONY: install-terminal-local install-terminal-global
install-terminal-local: ## Make WezTerm the default terminal, for this user
	@$(SCRIPTS)/install-terminal.sh --local

install-terminal-global: ## Seed the default-terminal preference for new users
	@$(SCRIPTS)/install-terminal.sh --global

.PHONY: install-tabs-local install-tabs-global
install-tabs-local: ## Hide the tab bar, the Omarchy look, for this user
	@$(SCRIPTS)/install-tabs.sh --local

install-tabs-global: ## Hide the tab bar system-wide (needs root)
	@$(SCRIPTS)/install-tabs.sh --global

.PHONY: install-global-config
install-global-config: ## System-wide config + WEZTERM_CONFIG_FILE (needs root)
	@$(SCRIPTS)/install-global-config.sh --global

.PHONY: install-screensaver-global
install-screensaver-global: ## Let Omarchy's screensaver run in WezTerm (needs root)
	@$(SCRIPTS)/install-screensaver.sh --global

.PHONY: install-screensaver-grace-global
install-screensaver-grace-global: ## Optional: ignore brief focus loss at startup
	@$(SCRIPTS)/install-screensaver-grace.sh --global

.PHONY: install-menus-local install-menus-global
install-menus-local: ## Add WezTerm to Omarchy's default-terminal menu (no root)
	@$(SCRIPTS)/install-menus.sh --local

install-menus-global: ## Teach Omarchy's terminal pickers about WezTerm (needs root)
	@$(SCRIPTS)/install-menus.sh --global

# ---------------------------------------------------------------------------
# uninstall / verification
# ---------------------------------------------------------------------------

.PHONY: uninstall uninstall-local uninstall-global
uninstall: ## Remove both installs
	@$(SCRIPTS)/uninstall.sh --local
	@$(SCRIPTS)/uninstall.sh --global

uninstall-local: ## Remove the per-user install
	@$(SCRIPTS)/uninstall.sh --local

uninstall-global: ## Remove the system-wide install (needs root)
	@$(SCRIPTS)/uninstall.sh --global

.PHONY: uninstall-tabs-local uninstall-tabs-global
uninstall-tabs-local: ## Restore the tab bar for this user
	@TABS_ONLY=1 $(SCRIPTS)/uninstall.sh --local

uninstall-tabs-global: ## Restore the tab bar system-wide (needs root)
	@TABS_ONLY=1 $(SCRIPTS)/uninstall.sh --global

.PHONY: uninstall-menus-local uninstall-menus-global
uninstall-menus-local: ## Remove WezTerm from the default-terminal menu for this user
	@MENUS_ONLY=1 $(SCRIPTS)/uninstall.sh --local

uninstall-menus-global: ## Remove the seeded menu row (needs root)
	@MENUS_ONLY=1 $(SCRIPTS)/uninstall.sh --global

.PHONY: check
check: ## Verify the live install: theme generates and the config loads
	@$(REPO)/test/smoke.sh

.PHONY: test
test: ## Test the installers themselves in a sandbox (no root, nothing touched)
	@$(REPO)/test/install-matrix.sh

.PHONY: dry-run
dry-run: ## Show what a local install would do, changing nothing
	@DRY_RUN=1 $(SCRIPTS)/install-all.sh --local

.PHONY: help
help: ## Show this help
	@printf '\nwezterm-omarchy -- WezTerm theming for Omarchy\n\n'
	@printf 'Targets:\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| sed -E 's/^([a-zA-Z_-]+):.*?## (.*)/\1|\2/' \
		| awk -F'|' '{ printf "  \033[36m%-34s\033[0m %s\n", $$1, $$2 }'
	@printf '\nVariables:\n'
	@printf '  \033[36m%-34s\033[0m %s\n' 'MODE=local|global' 'skip the prompt'
	@printf '  \033[36m%-34s\033[0m %s\n' 'DRY_RUN=1' 'print actions, change nothing'
	@printf '  \033[36m%-34s\033[0m %s\n' 'FORCE=1' 'replace config you wrote yourself'
	@printf '  \033[36m%-34s\033[0m %s\n' 'GLOBAL_SKIP_USER=1' 'global install without touching your account'
	@printf '  \033[36m%-34s\033[0m %s\n' 'UNINSTALL_GIST_LEFTOVERS=1' 'delete files the old install script left'
	@printf '\n'
