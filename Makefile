# Repo tasks for claude-skills.
# Run work through these targets, not by calling test files directly.

SHELL := /bin/bash

PLUGINS := ai-dev-assistant brand-content-design code-paper-test \
           code-quality-tools dev-guides-navigator drupal-ai-contrib \
           drupal-dev-framework drupal-htmx plugin-creation-tools

.PHONY: help test lint lint-baseline validate manifests ci \
        $(addprefix test-,$(PLUGINS))

help:
	@echo "make test              run every test in the repo"
	@echo "make test-<plugin>     run one plugin's tests"
	@echo "make lint              shellcheck, against scripts/lint-baseline.txt"
	@echo "make lint-baseline     rewrite that baseline (deliberate, then commit)"
	@echo "make validate          check the catalog and each plugin with the claude CLI"
	@echo "make manifests         check plugin.json and marketplace.json agree"
	@echo "make ci                all four checks, same as the PR check"
	@echo ""
	@echo "lint reports a warning that is not in the baseline as a failure."
	@echo "A baseline warning that is gone is reported as fixed and passes."
	@echo "validate fails on errors; warnings print without failing."
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

# Runs all four even when one fails, so a single run reports every problem
# instead of stopping at the first. As prerequisites (ci: manifests lint
# validate test) make would abort on the first failure and a lint regression
# would hide whether the tests pass. .github/workflows/ci.yml runs the same
# four checks the same way, so this really is the PR check.
ci:
	@fail=""; \
	for target in manifests lint validate test; do \
	  printf '\n==> make %s\n' "$$target"; \
	  $(MAKE) --no-print-directory "$$target" || fail="$$fail $$target"; \
	done; \
	printf '\n----\n'; \
	if [ -n "$$fail" ]; then \
	  printf 'ci: FAILED:%s\n' "$$fail" >&2; \
	  exit 1; \
	fi; \
	printf 'ci: all four checks passed\n'
