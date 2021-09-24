#!/usr/bin/env zsh

repo="$CODE/vagrant-docker-box"
caller_dir="$PWD"

function prepare_repo() {
  cd "$CODE"
  if [[ ! -d "$repo" ]]; then
    git clone git@github.com:sha1n/vagrant-docker-box.git
  fi
  cd vagrant-docker-box

  return $?
}

function start_box() {
  vagrant up
  return $?
}

prepare_repo &&
  start_box &&
  export DOCKER_HOST=tcp://192.168.10.101:2375 &&
  cd "$caller_dir"
