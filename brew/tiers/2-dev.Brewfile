# Homebrew 6 refuses untrusted third-party taps (HOMEBREW_REQUIRE_TAP_TRUST default).
tap "sha1n/tap", trusted: true

# Runtime manager: the runtimes come from config/mise/profile.toml, not from Homebrew
brew "mise"
# Python CLI tools install as uv tools, not with pipx
brew "uv"

# Tools
brew "make"
brew "go-task"
brew "shellcheck"

# AI and agents
brew "openspec"
cask "antigravity-cli"
cask "sha1n/tap/acdc-mcp", trusted: true
cask "sha1n/tap/repulse", trusted: true

# Language servers for nvim. basedpyright depends on the Homebrew node formula, which
# openspec already pulls in; mise still owns the node that projects use, so add no node
# entry here. typescript is TypeScript 7, whose native `tsc --lsp` needs no node; the
# typescript-language-server formula cannot use it and fails outside a project with its
# own typescript package.
brew "gopls"
brew "basedpyright"
brew "typescript"
# nvim language server and formatter for Lua; config/nvim/init.lua enables each server whose binary is on PATH
brew "lua-language-server"
brew "stylua"
# nvim-treesitter compiles its parsers with this CLI
brew "tree-sitter-cli"
