BASEDIR := $(shell pwd)

test:
	$(BASEDIR)/tests/run_tests.sh

update_submodules:
	git submodule update --recursive --remote

compile:
	@echo "Compiling zsh files to zwc bytecode..."
	@zsh -c 'for f in $(BASEDIR)/load.zsh $(BASEDIR)/include/*(.) $(BASEDIR)/scripts/lib.zsh; do [[ $$f == *.zwc ]] && continue; zcompile $$f 2>/dev/null; done'
	@echo "Done."

clean_zwc:
	@echo "Removing zwc bytecode files..."
	@find $(BASEDIR) -name "*.zwc" -delete
	@echo "Done."
