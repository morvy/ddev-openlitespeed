#!/usr/bin/env bats

# Bats testing framework: https://bats-core.readthedocs.io/en/stable/
# Local run (from the add-on root, with bats-core/-assert/-file/-support installed):
#   bats ./tests/test.bats
# Exclude the release test:
#   bats ./tests/test.bats --filter-tags '!release'

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=morvy/ddev-openlitespeed

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-ddev-openlitespeed"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"

  # Minimal PHP app served from the project root (empty docroot).
  cat > index.php <<'PHP'
<?php echo "ddev-openlitespeed-ok software=" . ($_SERVER['SERVER_SOFTWARE'] ?? 'unknown');
PHP

  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  # The project must be reachable through ddev-router with a 200.
  run curl -sfI "https://${PROJNAME}.ddev.site"
  assert_success
  assert_output --partial "200"

  # PHP must actually execute via lsphp, and the server must be OpenLiteSpeed.
  run curl -sf "https://${PROJNAME}.ddev.site/"
  assert_success
  assert_output --partial "ddev-openlitespeed-ok"
  assert_output --partial "LiteSpeed"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
