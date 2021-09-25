#!/usr/bin/env zsh

autoload -U colors && colors
local script_dir=${0:a:h}
local dotzshrc="$HOME/.zshrc"
local dotfiles_dir="$script_dir/dotfiles"

function error() {
  print "$fg[red]Error:$reset_color $1"
}

function warn() {
  print "$fg[yellow]Warning:$reset_color $1"
}

function validate() {
  print "Observing $dotzshrc..."
  # We are not going to create .zshrc. If it doesn't exist something is probably off
  if [[ ! -f "$dotzshrc" ]]; then
    warn "the file '$dotzshrc' does not exist. An empty one will be created."
    touch "$dotzshrc"
    return 1
  fi

  local existing_source=$(grep -e '^source .*/\.include' "$dotzshrc")
  if [[ ! -z "$existing_source" ]]; then
    error "the following 'source' command is already in your .zshrc profile: $existing_source"
    return 1
  fi
}

function install() {
  print "Installing profile..."
  echo "source '$script_dir/.include'" >>"$dotzshrc"
  if [[ "$?" == "0" ]]; then
    echo "Installed successfully!"
    echo "To verify installation start new session or source $dotzshrc"
  fi
}

function link_dotfile() {
  print "Linking $1..."
  if [[ -f "$HOME/$1" ]]; then
    warn "the file '${HOME}/${1}' already exists. Skipping..."
  else
    ln -s "$dotfiles_dir/$1" "$HOME/$1"
    return "$?"
  fi

}

function link_dotfiles() {
  print "Linking dor files..."
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    link_dotfile "$file"
  done
}

link_dotfiles
validate && install && print "Done!" || warn "Skipped!"
