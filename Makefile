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
