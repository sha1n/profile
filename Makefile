BASEDIR := $(shell pwd)

test: ensure_submodules
	@-./tests/zsh-scriptest/run_tests.sh $(BASEDIR)/tests

ensure_submodules:
	@git submodule update --recursive