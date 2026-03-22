TESTS_DIR := tests
INIT := $(TESTS_DIR)/minimal_init.lua
TEST_FILES := $(wildcard $(TESTS_DIR)/*.test.lua)

.PHONY: test
test:
	@passed=0; failed=0; failed_files=""; \
	for f in $(TEST_FILES); do \
		if nvim --headless -u $(INIT) \
			-c "set rtp+=." \
			-c "runtime plugin/plenary.vim" \
			-c "lua require('plenary.busted').run('$$f')" \
			2>&1; then \
			passed=$$((passed + 1)); \
		else \
			failed=$$((failed + 1)); \
			failed_files="$$failed_files\n  $$f"; \
		fi; \
	done; \
	total=$$((passed + failed)); \
	echo ""; \
	echo "=== Test Summary: $$passed/$$total files passed ==="; \
	if [ $$failed -gt 0 ]; then \
		printf "Failed:\n$$failed_files\n"; \
		exit 1; \
	fi

.PHONY: test-file
test-file:
	@nvim --headless -u $(INIT) \
		-c "set rtp+=." \
		-c "runtime plugin/plenary.vim" \
		-c "lua require('plenary.busted').run('$(FILE)')"

.PHONY: vimdoc-check
vimdoc-check:
	@set -euo pipefail; \
	sed '/^# md-view\.nvim$$/d' README.md > .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	sed 's/^#/##/' docs/ARCHITECTURE.md >> .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	cat docs/recipes/picker-integration.md >> .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	cat docs/recipes/auto-open.md >> .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	cat docs/recipes/filetypes.md >> .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	cat docs/recipes/single-page-mode.md >> .doc-source.md; \
	printf "\n\n" >> .doc-source.md; \
	sed 's/^#/##/' docs/options.md >> .doc-source.md; \
	dupes=$$(grep -i '^# [^#]' .doc-source.md | tr '[:upper:]' '[:lower:]' | sort | uniq -d); \
	if [ -n "$$dupes" ]; then \
		echo "ERROR: duplicate H1 headings found:"; \
		echo "$$dupes"; \
		rm -f .doc-source.md; \
		exit 1; \
	fi; \
	echo "OK: no duplicate H1 headings"; \
	rm -f .doc-source.md

.PHONY: hooks
hooks:
	chmod +x .githooks/pre-commit
	git config core.hooksPath .githooks
	@echo "Git hooks configured. Pre-commit hook is now active."
