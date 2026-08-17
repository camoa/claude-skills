# Repo tasks for claude-skills.
# Run work through these targets, not by calling test files directly.

SHELL := /bin/bash

PLUGINS := ai-dev-assistant brand-content-design code-paper-test \
           code-quality-tools dev-guides-navigator drupal-ai-contrib \
           drupal-dev-framework drupal-htmx plugin-creation-tools

# Plugins that actually own tests. `make test-<plugin>` exists for all nine,
# but run-tests.sh fails a run that executed nothing ("nothing ran, so
# nothing passed"), so the targets for the rest cannot succeed today. `make
# help` says which is which rather than advertising six targets that only
# ever exit 1. Derived from the tree, not hardcoded, so it stops being true
# the moment someone adds a test.
TESTED_PLUGINS := $(sort $(foreach p,$(PLUGINS),\
  $(if $(shell git ls-files '$(p)' 2>/dev/null | grep -E '/tests/.*\.sh$$|-spec\.sh$$|-spec\.mjs$$' | head -1),$(p))))
UNTESTED_PLUGINS := $(filter-out $(TESTED_PLUGINS),$(PLUGINS))

.PHONY: help test lint lint-baseline validate manifests outputs ci \
        $(addprefix test-,$(PLUGINS))

help:
	@echo "make test              run every test in the repo"
	@echo "make test-<plugin>     run one plugin's tests (see below)"
	@echo "make lint              shellcheck, against scripts/lint-baseline.txt"
	@echo "make lint-baseline     rewrite that baseline (deliberate, then commit)"
	@echo "make validate          check the catalog and each plugin with the claude CLI"
	@echo "make manifests         check plugin.json and marketplace.json agree"
	@echo "make outputs           check every command says what it writes"
	@echo "make ci                all five checks, same as the PR check"
	@echo ""
	@echo "lint reports a warning that is not in the baseline as a failure."
	@echo "A baseline warning that is gone is reported as fixed and passes."
	@echo "validate fails on errors; warnings print without failing."
	@echo "outputs fails on a command file with no '## Output' section."
	@echo ""
	@echo "make test-<plugin> works for: $(TESTED_PLUGINS)"
	@echo ""
	@echo "For these, test-<plugin> cannot pass today and exits 1:"
	@echo "  $(UNTESTED_PLUGINS)"
	@echo "That is the zero-test floor reporting honestly, not a bug: a run"
	@echo "that executed nothing has not passed anything. Adding a test file"
	@echo "under the plugin moves it to the working list automatically."
	@echo "(brand-content-design is the odd one out: its tests need pytest"
	@echo "and npm install, and they skip - not run - without them.)"
	@echo ""
	@echo "plugins: $(PLUGINS)"

test:
	@bash scripts/run-tests.sh

$(addprefix test-,$(PLUGINS)): test-%:
	@bash scripts/run-tests.sh $*

lint:
	@bash scripts/lint-shell.sh

lint-baseline:
	@bash scripts/lint-shell.sh --update-baseline

validate:
	@bash scripts/validate-plugins.sh

manifests:
	@python3 scripts/check-manifests.py

# Its own target rather than a rule inside check-manifests.py: that script
# compares plugin.json against the catalog entry and knows nothing about
# command bodies, and CLAUDE.md documents each target by what it can fail on,
# which only works while a target has one subject. Separate also means this
# can fail on its own line in CI instead of inside a manifest verdict.
outputs:
	@bash scripts/check-outputs.sh

# Runs all five even when one fails, so a single run reports every problem
# instead of stopping at the first. As prerequisites (ci: manifests outputs
# lint validate test) make would abort on the first failure and a lint
# regression would hide whether the tests pass. .github/workflows/ci.yml runs
# the same five checks the same way, so this really is the PR check.
ci:
	@fail=""; \
	for target in manifests outputs lint validate test; do \
	  printf '\n==> make %s\n' "$$target"; \
	  $(MAKE) --no-print-directory "$$target" || fail="$$fail $$target"; \
	done; \
	printf '\n----\n'; \
	if [ -n "$$fail" ]; then \
	  printf 'ci: FAILED:%s\n' "$$fail" >&2; \
	  exit 1; \
	fi; \
	printf 'ci: all five checks passed\n'
