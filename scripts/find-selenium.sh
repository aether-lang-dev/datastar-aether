#!/bin/sh
# Locate the Aether Selenium binding, and print its --lib path segments.
#
# The component tests need three directories from the Selenium port:
# aether/ (the binding), selenium_core/ (the engine) and
# selenium_core/drivermgr/ (driver resolution). Where those live depends
# on who you are:
#
#   - Most people BUY IT IN. `ae add` installs packages under
#     ~/.aether/packages/<host>/<user>/<repo>, so that is checked.
#   - Some people DEVELOP IT alongside this repo, on the same box, and
#     want their edits picked up without publishing. A sibling checkout
#     is checked first for exactly that reason: if you have both, the
#     working copy is what you meant.
#   - Anyone can override with SELENIUM=/path, which wins over both.
#
# Prints the path on stdout and exits 0, or explains all three options on
# stderr and exits 1. Never guesses silently: a missing binding surfaces
# as this message rather than as a compile error about an unknown module.
set -u

# A directory is the binding if it has the three pieces we import.
is_binding() {
    [ -f "$1/aether/webdriver.ae" ] &&
    [ -d "$1/selenium_core" ] &&
    [ -d "$1/selenium_core/drivermgr" ]
}

# 1. Explicit override — an answer, not a guess, so a wrong one is loud.
if [ -n "${SELENIUM:-}" ]; then
    if is_binding "$SELENIUM"; then
        echo "$SELENIUM"
        exit 0
    fi
    echo "SELENIUM=$SELENIUM does not look like the Aether Selenium port" >&2
    echo "  (expected \$SELENIUM/aether/webdriver.ae and \$SELENIUM/selenium_core/)" >&2
    exit 1
fi

# 2. A sibling checkout — the local-development case, preferred over the
#    package so that edits under test are the ones that run.
for sibling in ../selenium ../selaenium; do
    if is_binding "$sibling"; then
        echo "$sibling"
        exit 0
    fi
done

# 3. The package cache, where `ae add` puts things. It stores by full source
#    path: packages/<host>/<user>/<repo> — e.g.
#    packages/github.com/aether-lang-dev/selaenium — so the binding sits THREE
#    levels down, not two. Glob both depths (and *sela*/*selen* spellings) so a
#    published `ae add github.com/aether-lang-dev/selaenium@vX` is actually found.
cache="${AETHER_HOME:-$HOME/.aether}/packages"
if [ -d "$cache" ]; then
    for candidate in \
        "$cache"/*/*/*sel*nium* \
        "$cache"/*/*sel*nium* ; do
        if is_binding "$candidate"; then
            echo "$candidate"
            exit 0
        fi
    done
fi

cat >&2 <<MSG
Cannot find the Aether Selenium binding — the component tests need it.

Looked in, in order:
  1. \$SELENIUM              (unset)
  2. ../selenium             a sibling checkout, for developing it alongside this repo
  3. $cache
                             where 'ae add' installs packages

Pick one:
  task test-component SELENIUM=/path/to/selenium
  git clone <the Aether Selenium port> ../selenium
  ae add <the published package>

The offline suites ('task test') need none of this.
MSG
exit 1
