BASEDIR := $(shell pwd)

test:
	$(BASEDIR)/tests/run_tests.sh

update_submodules:
	git submodule update --recursive --remote
