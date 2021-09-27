BASEDIR := $(shell pwd)

test:
	@-$(BASEDIR)/tests/zsh-scriptest/run_tests.sh $(BASEDIR)/tests

update_submodules:
	@git submodule update --recursive --remote
