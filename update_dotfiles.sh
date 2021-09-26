#!/usr/bin/env zsh

autoload -U colors && colors
local script_dir=${0:a:h}
local dotfiles_dir="$script_dir/dotfiles"

function error() {
  print "$fg[red]Error:$reset_color $1"
}

function warn() {
  print "$fg[yellow]Warning:$reset_color $1"
}

function green() {
  print "$fg[green]$1$reset_color"
}


function link_dotfile() {
  print "Linking $1..."
  ln -sf "$dotfiles_dir/$1" "$HOME/$1"
  return "$?"
}

function link_dotfiles() {
  print "Linking dot files..."
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    if [[ "$file" != ".gitconfig" ]]; then
      link_dotfile "$file" && green "ok!" || warn "failed!"
    fi
  done
}

link_dotfiles
green "Done!"
