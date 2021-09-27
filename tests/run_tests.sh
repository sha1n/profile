#!/usr/bin/env zsh

export SHA1N_PROFILE_TESTS_HOME="${${(%):-%x}:a:h}"

"$SHA1N_PROFILE_TESTS_HOME/zsh-scriptest/run_tests.sh" "$SHA1N_PROFILE_TESTS_HOME"