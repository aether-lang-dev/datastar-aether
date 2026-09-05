#!/bin/sh
# Locate the Aether Selenium binding, and print its --lib path segments.
#
# The component tests need three directories from the Selenium port:
# aether/ (the binding), selenium_core/ (the engine) and
# selenium_core/drivermgr/ (driver resolution). Where those live depends
# on who you are:
#
#   - $SELENIUM=/path wins over everything. An explicit answer.
#   - Otherwise the PINNED PACKAGE, from `ae add`, under
#     ~/.aether/packages/<host>/<user>/<repo>. This is the default
#     because a tag is the same bytes for everyone.
#   - A sibling checkout is used ONLY when asked for (SELAENIUM_LOCAL=1).
#     It is not auto-detected: a working copy silently overriding a
#     pinned dependency is how a green run here becomes a red one in CI.
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

# 2. A sibling checkout, ONLY when explicitly asked for.
#
#    This used to come before the package, on the reasoning that someone
#    editing the binding wants their edits under test. That reasoning is
#    sound and the mechanism was not: an auto-detected sibling overrides a
#    pinned dependency SILENTLY. On a two-box workflow that is how a run
#    goes green against engine changes committed on one box and never
#    pushed, then fails in CI, which only has the package.
#
#    It is also the same failure shape as the bug that made this script's
#    package branch dead for its first week: a fallback quietly doing
#    something other than what the caller assumed. So the sibling is now
#    opt-in — set SELENIUM, or SELAENIUM_LOCAL=1 to take the sibling
#    without typing its path.
if [ "${SELAENIUM_LOCAL:-0}" = "1" ]; then
    for sibling in ../selaenium ../selenium; do
        if is_binding "$sibling"; then
            echo "$sibling"
            exit 0
        fi
    done
    echo "SELAENIUM_LOCAL=1 but no ../selaenium or ../selenium checkout found" >&2
    exit 1
fi

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
  1. \$SELENIUM                 (unset)
  2. ../selaenium              (only with SELAENIUM_LOCAL=1, which is unset)
  3. $cache
                               where 'ae add' installs packages

Get it the reproducible way:
  ae add github.com/aether-lang-dev/selaenium@v0.2.0

Or point at a working copy, explicitly:
  task test-component SELENIUM=/path/to/selaenium
  SELAENIUM_LOCAL=1 task test-component     # takes ../selaenium if present

A sibling checkout is NOT picked up automatically. It used to be, and a
silent local override is how a green run here becomes a red one in CI.

The offline suites ('task test') need none of this.
MSG
exit 1
