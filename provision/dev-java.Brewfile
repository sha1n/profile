# Java toolchain. Single JDK: the temurin cask registers with
# /usr/libexec/java_home, which is what export_openjdk_formula and IntelliJ read.
# The keg-only openjdk@N formulae never register there and are not declared.
brew "maven"
# In this layer, not essentials: `brew deps` shows 30 formulae including openjdk,
# cairo, harfbuzz, libtiff and webp (D10).
brew "openapi-generator"

cask "temurin@25"
cask "intellij-idea"
