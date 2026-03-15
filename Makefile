TESTS_DIR := tests
INIT := $(TESTS_DIR)/minimal_init.lua
TEST_FILES := $(wildcard $(TESTS_DIR)/*.test.lua)

.PHONY: test
test:
	@for f in $(TEST_FILES); do \
		nvim --headless -u $(INIT) \
			-c "set rtp+=." \
			-c "runtime plugin/plenary.vim" \
			-c "lua require('plenary.busted').run('$$f')" ; \
	done

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
