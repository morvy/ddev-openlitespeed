#!/usr/bin/env bats

# Bats testing framework: https://bats-core.readthedocs.io/en/stable/
# Local run (needs bats-core, bats-assert, bats-file, bats-support):
#   bats ./tests/test.bats --filter-tags php84
#   bats ./tests/test.bats --filter-tags '!release,!php86'   # all but release and PHP 8.6 (needs DDEV HEAD)
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
  export CI=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
}

# Minimal app: reports the HTTPS server vars and confirms the DDEV environment
# reaches PHP (IS_DDEV_PROJECT is what framework settings files gate on).
# parity.php reports what the parity checks compare against DDEV's CLI PHP.
install_index() {
  cat > index.php <<'PHP'
<?php
foreach (['HTTPS', 'SERVER_PORT', 'REQUEST_SCHEME', 'SERVER_SOFTWARE'] as $k) {
  echo "$k=" . (isset($_SERVER[$k]) ? $_SERVER[$k] : '(unset)') . "\n";
}
echo "IS_DDEV=" . (getenv('IS_DDEV_PROJECT') ?: 'unset') . "\n";
echo "phpver=" . PHP_VERSION . "\n";
echo "ddev-openlitespeed-ok\n";
PHP
  cat > parity.php <<'PHP'
<?php
$ext = array_unique(array_diff(array_map('strtolower', get_loaded_extensions()), ['litespeed', 'cgi-fcgi', 'cli']));
sort($ext, SORT_STRING);
echo "ext=" . implode(',', $ext) . "\n";
echo "tz=" . ini_get('date.timezone') . "\n";
echo "max_input_vars=" . ini_get('max_input_vars') . "\n";
echo "xdebug=" . (extension_loaded('xdebug') ? 'on' : 'off') . "\n";
echo "xhprof=" . (extension_loaded('xhprof') ? 'on' : 'off') . "\n";
PHP
  # For the error page checks: an app's own 404, and a directory without an index.
  printf '<?php http_response_code(404); echo "app-404\\n";\n' > app404.php
  mkdir -p noindex
  assert_file_exist index.php
}

# Fetch parity.php, retrying while lsphp restarts after `ddev xdebug`/`ddev xhprof`.
# Few retries, so a server that stays down after the daemon restart fails the test
# (a down server fails fast). -m 10: with xhprof on, DDEV's xhgui prepend makes each
# request take ~4s when no xhgui service is running.
parity() {
  local out=""
  for _ in $(seq 1 10); do
    out="$(curl -sf -m 10 "https://${PROJNAME}.ddev.site/parity.php" || true)"
    [ -n "${out}" ] && break
    sleep 1
  done
  echo "${out}"
}

# lsphp must run DDEV's PHP setup, same as nginx-fpm/apache-fpm (docs/php-parity.md).
parity_checks() {
  # Same extensions as DDEV's php-fpm (shared conf.d). Not the CLI: Debian builds
  # pcntl into the CLI binary.
  local fpm_ext
  fpm_ext="$(ddev exec "php-fpm\${DDEV_PHP_VERSION} -m" | tr -d '\r' | grep -v '^\[' | grep -v '^$' \
    | tr 'A-Z' 'a-z' | grep -vxE 'cgi-fcgi|litespeed' | LC_ALL=C sort -u | paste -sd, -)"
  run parity
  assert_output --partial "ext=${fpm_ext}"$'\n'
  # DDEV's start-time php.ini edit (timezone) reaches lsphp.
  local cli_tz
  cli_tz="$(ddev exec "php -r 'echo ini_get(\"date.timezone\");'")"
  assert_output --partial "tz=${cli_tz}"$'\n'
  # .ddev/php/*.ini overrides reach lsphp.
  assert_output --partial "max_input_vars=4321"

  # ddev xdebug / ddev xhprof toggle lsphp, and lsphp survives the daemon restart.
  # Skipped for an extension the image doesn't ship for this PHP version yet
  # (e.g. xdebug for PHP 8.6), where DDEV itself refuses the toggle.
  local ext
  for ext in xdebug xhprof; do
    if ! ddev exec "test -f /etc/php/\${DDEV_PHP_VERSION}/mods-available/${ext}.ini"; then
      echo "# ${ext} not available for this PHP version, skipping its toggle" >&3
      continue
    fi
    run ddev "${ext}" on
    assert_success
    run parity
    assert_output --partial "${ext}=on"
    run ddev "${ext}" off
    assert_success
    run parity
    assert_output --partial "${ext}=off"
  done
  # Restart the daemons the way those toggles do, so the checks below always run
  # after at least one restart.
  run ddev exec "supervisorctl restart 'webextradaemons:*'"
  assert_success
  run parity
  assert_output --partial "xdebug=off"
  run ddev exec "supervisorctl status webextradaemons:lsphp"
  assert_output --partial "RUNNING"
  # The daemon restarts must not leave an old OLS wrapper or server behind.
  run ddev exec "supervisorctl status webextradaemons:openlitespeed"
  assert_output --partial "RUNNING"
  run ddev exec "pgrep -cf '^(/usr)?/bin/bash /usr/local/bin/ddev-openlitespeed-start\$'"
  assert_output --regexp '^1[[:space:]]*$'
  run ddev exec "pgrep -cf '^openlitespeed \\(lshttpd - main\\)'"
  assert_output --regexp '^1[[:space:]]*$'
}

# DDEV's error pages (in the web image since DDEV v1.25.4) for OLS's own 404s and
# index-less directories; the app's own 404 must pass through untouched.
error_page_checks() {
  if ! ddev exec "test -f /usr/local/share/ddev-webserver-404-error.html"; then
    echo "# no DDEV error pages in this DDEV version, skipping error page checks" >&3
    return 0
  fi
  run curl -s -D- "https://${PROJNAME}.ddev.site/missing-file.txt"
  assert_output --partial "HTTP/2 404"
  assert_output --partial "x-ddev-404-source: ddev-webserver (openlitespeed)"

  run curl -s -D- "https://${PROJNAME}.ddev.site/noindex/"
  assert_output --partial "HTTP/2 403"
  assert_output --partial "x-ddev-403-source: ddev-webserver (openlitespeed)"
  refute_output --partial "(apache)"

  run curl -s -D- "https://${PROJNAME}.ddev.site/app404.php"
  assert_output --partial "HTTP/2 404"
  assert_output --partial "app-404"
  refute_output --partial "x-ddev-404-source"
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
  # DDEV environment must reach PHP or framework DB config fails.
  assert_output --partial "IS_DDEV=true"

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
  mkdir -p .ddev/php
  printf 'max_input_vars = 4321\n' > .ddev/php/zz-parity-test.ini
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} (PHP ${1}) in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks "${1}"
  error_page_checks
  parity_checks
}

# bats test_tags=php56
@test "PHP 5.6" {
  set -eu -o pipefail
  install_and_check "5.6"
}

# bats test_tags=php74
@test "PHP 7.4" {
  set -eu -o pipefail
  install_and_check "7.4"
}

# bats test_tags=php83
@test "PHP 8.3" {
  set -eu -o pipefail
  install_and_check "8.3"
}

# bats test_tags=php84
@test "PHP 8.4" {
  set -eu -o pipefail
  install_and_check "8.4"
}

# bats test_tags=php85
@test "PHP 8.5" {
  set -eu -o pipefail
  install_and_check "8.5"
}

# Needs a DDEV with PHP 8.6 support (CI runs it on DDEV HEAD only).
# bats test_tags=php86
@test "PHP 8.6" {
  set -eu -o pipefail
  install_and_check "8.6"
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
