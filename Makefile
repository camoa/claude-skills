# Repo tasks for claude-skills.
# Run work through these targets, not by calling test files directly.

SHELL := /bin/bash

PLUGINS := ai-dev-assistant brand-content-design code-paper-test \
           code-quality-tools dev-guides-navigator drupal-ai-contrib \
           drupal-dev-framework drupal-htmx plugin-creation-tools

.PHONY: help test lint validate manifests ci $(addprefix test-,$(PLUGINS))

help:
	@echo "make test              run every test in the repo"
	@echo "make test-<plugin>     run one plugin's tests"
	@echo "make lint              check shell scripts with shellcheck"
	@echo "make validate          check plugin structure with the claude CLI"
	@echo "make manifests         check versions and descriptions match"
	@echo "make ci                everything above, same as the PR check"
	@echo ""
	@echo "plugins: $(PLUGINS)"

test:
	@bash scripts/run-tests.sh

$(addprefix test-,$(PLUGINS)): test-%:
	@bash scripts/run-tests.sh $*

lint:
	@bash scripts/lint-shell.sh

validate:
	@bash scripts/validate-plugins.sh

manifests:
	@python3 scripts/check-manifests.py

ci: manifests lint validate test
