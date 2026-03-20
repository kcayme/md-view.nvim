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

.PHONY: hooks
hooks:
	chmod +x .githooks/pre-commit
	git config core.hooksPath .githooks
	@echo "Git hooks configured. Pre-commit hook is now active."
