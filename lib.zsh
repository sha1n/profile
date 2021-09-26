#!/usr/bin/env zsh
autoload -U colors && colors

function error() {
  print "$fg[red]Error:$reset_color $1"
}

function warn() {
  print "$fg[yellow]Warning:$reset_color $1"
}

function info() {
  print "$fg[cyan]Info:$reset_color $1"
}

function green() {
  print "$fg[green]$1$reset_color"
}
