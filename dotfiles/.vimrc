set nocompatible
set termguicolors
set background=dark
colorscheme solarized

syntax enable

" indent    allow backspacing over autoindent
" eol       allow backspacing over line breaks (join lines)
" start     allow backspacing over the start of insert; CTRL-W and CTRL-U stop once at the start of insert.
set backspace=indent,eol,start

" show line numbers
set number
set relativenumber

" highlight cursor line
" set cursorline

" search settings
" search as you type
set incsearch
" highlight matches
set hlsearch
" ignore case when searching
set ignorecase
" unless you type a capital letter
set smartcase

set foldenable

" tab size
set tabstop=2
" tab size for editing
set softtabstop=2
" use spaces to represent tabs <-- bad for Makefile
" set expandtab

set autoindent
set autoread

" UX Improvements
set signcolumn=yes
set updatetime=300
set undofile

" clipboard integration
set clipboard=unnamed