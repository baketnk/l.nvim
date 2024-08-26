.PHONY: all
all: test

.PHONY: test
test:
	@echo "running l.nvim tests"
	@nvim --headless -c "PlenaryBustedDirectory tests/lnvim/ { minimal_init = 'tests/minimal.lua' }"
	@echo "Completed: @?"

# .PHONY tells Make that this is not a file target
