#!/usr/bin/env bats

# Bats testing framework: https://bats-core.readthedocs.io/en/stable/
# Local run (needs bats-core, bats-assert, bats-file, bats-support):
#   bats ./tests/test.bats --filter-tags php84
#   bats ./tests/test.bats --filter-tags '!release'   # everything but the release test
# Debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=morvy/ddev-openlitespeed

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p ~/tmp
  export TESTDIR="$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
}

# Minimal app that reports the HTTPS-related server vars PHP sees.
install_index() {
  cat > index.php <<'PHP'
<?php
foreach (['HTTPS', 'SERVER_PORT', 'REQUEST_SCHEME', 'SERVER_SOFTWARE'] as $k) {
  echo "$k=" . ($_SERVER[$k] ?? '(unset)') . "\n";
}
echo "phpver=" . PHP_VERSION . "\n";
echo "ddev-openlitespeed-ok\n";
PHP
  assert_file_exist index.php
}

# $1 = expected PHP version prefix (e.g. "7.4")
health_checks() {
  # PHP served by OpenLiteSpeed via lsphp, over HTTPS through ddev-router.
  run curl -sfI "https://${PROJNAME}.ddev.site"
  assert_success
  assert_output --partial "HTTP/2 200"
  assert_output --regexp "[Ss]erver: LiteSpeed"

  run curl -sf "https://${PROJNAME}.ddev.site/"
  assert_success
  assert_output --partial "ddev-openlitespeed-ok"
  assert_output --partial "SERVER_SOFTWARE=LiteSpeed"
  assert_output --partial "phpver=${1}"
  # HTTPS server vars must be correct behind the TLS-terminating router.
  assert_output --partial "HTTPS=on"
  assert_output --partial "SERVER_PORT=443"

  # Plain HTTP must NOT report HTTPS=on.
  run curl -sf "http://${PROJNAME}.ddev.site/"
  assert_success
  refute_output --partial "HTTPS=on"
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

install_and_check() {  # $1 = php version
  run ddev config --php-version="${1}"
  assert_success
  install_index
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} (PHP ${1}) in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks "${1}"
}

# bats test_tags=php74
@test "PHP 7.4 (bookworm lsphp sidecar)" {
  set -eu -o pipefail
  install_and_check "7.4"
}

# bats test_tags=php83
@test "PHP 8.3 (native lsphp)" {
  set -eu -o pipefail
  install_and_check "8.3"
}

# bats test_tags=php84
@test "PHP 8.4 (native lsphp)" {
  set -eu -o pipefail
  install_and_check "8.4"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  install_index
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks "8"
}
