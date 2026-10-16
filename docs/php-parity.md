# PHP parity: OpenLiteSpeed vs DDEV's nginx-fpm / apache-fpm

Measured 2026-10-16 on DDEV v1.25.4, PHP 8.4, one throwaway `php` project switched
nginx-fpm → apache-fpm → `ddev-openlitespeed` v1.0.3 (local checkout), then a prototype
of the fixes below. Each column is what PHP reports **over HTTP** (`get_loaded_extensions()`,
`ini_get_all()`); CLI `php -m` was identical in all setups (the CLI is DDEV's in every case).

**Summary:** v1.0.3 runs LiteSpeed's own `lsphp84` build with its own ini tree. That loses
12 extensions DDEV ships, DDEV's start-time php.ini edits (timezone), `.ddev/php/*.ini`
overrides, and `ddev xdebug` / `ddev xhprof`. Running OLS on **sury's
`php<ver>-litespeed`** (the LiteSpeed SAPI built from the same PHP packages as DDEV's
php-fpm) and sharing the fpm ini/conf.d gives full parity — prototype verified, see
[Fixes](#fixes).

**Status:** fixes 1–4 are implemented in the add-on after v1.0.3 (the sidecar is gone).
The test suite (`tests/test.bats`) now checks extension parity against `php-fpm -m`
(not the CLI: Debian compiles `pcntl` into the CLI binary), the timezone, a `.ddev/php`
override and the xdebug/xhprof toggles.

## DDEV features

| Feature | nginx-fpm | apache-fpm | OLS v1.0.3 | OLS + sury SAPI (prototype) |
|---|---|---|---|---|
| PHP build | Debian/sury 8.4.24 | Debian/sury 8.4.24 | LiteSpeed lsphp 8.4.26 | Debian/sury 8.4.26 (`lsphp8.4`) |
| Loaded extensions | 66 | 66 | 58 | 66 |
| php.ini | `fpm/php.ini` | `fpm/php.ini` | build-time copy of `fpm/php.ini` | `litespeed/php.ini` (= fpm's) |
| `date.timezone` from DDEV / `TZ` | ✓ Europe/Bratislava | ✓ | ✗ `UTC` (copy taken before `start.sh` edits) | ✓ |
| `.ddev/php/*.ini` overrides | ✓ | ✓ | ✗ | ✓ (tested `max_input_vars = 4321`) |
| `ddev xdebug on` / `off` | ✓ | ✓ | ✗ never loads | ✓ |
| `ddev xhprof on` / `off` | ✓ | ✓ | ✗ never loads | ✓ |
| `sendmail_path` → Mailpit | ✓ | ✓ | ✓ (copied) | ✓ |
| `IS_DDEV_PROJECT` / DDEV env in PHP | ✓ | ✓ | ✓ | ✓ |
| PHP versions | 5.6–8.5 | 5.6–8.5 | 7.4, 8.0 (sidecar), 8.1–8.5 | 5.6–8.5 in the web container (`php5.6-litespeed` … `php8.5-litespeed` all exist in sury for trixie) |

## Extensions (over HTTP)

Bold = differs between fpm and OLS v1.0.3.

| Extension | nginx-fpm | apache-fpm | OLS v1.0.3 | OLS + sury SAPI (prototype) |
|---|---|---|---|---|
| **apcu** | ✓ | ✓ | — | ✓ |
| bcmath | ✓ | ✓ | ✓ | ✓ |
| bz2 | ✓ | ✓ | ✓ | ✓ |
| calendar | ✓ | ✓ | ✓ | ✓ |
| **cgi-fcgi** | ✓ | ✓ | — | — |
| Core | ✓ | ✓ | ✓ | ✓ |
| ctype | ✓ | ✓ | ✓ | ✓ |
| curl | ✓ | ✓ | ✓ | ✓ |
| date | ✓ | ✓ | ✓ | ✓ |
| dom | ✓ | ✓ | ✓ | ✓ |
| **enchant** | — | — | ✓ | — |
| exif | ✓ | ✓ | ✓ | ✓ |
| **FFI** | ✓ | ✓ | — | ✓ |
| fileinfo | ✓ | ✓ | ✓ | ✓ |
| filter | ✓ | ✓ | ✓ | ✓ |
| ftp | ✓ | ✓ | ✓ | ✓ |
| gd | ✓ | ✓ | ✓ | ✓ |
| gettext | ✓ | ✓ | ✓ | ✓ |
| **gmp** | — | — | ✓ | — |
| hash | ✓ | ✓ | ✓ | ✓ |
| iconv | ✓ | ✓ | ✓ | ✓ |
| igbinary | ✓ | ✓ | ✓ | ✓ |
| imagick | ✓ | ✓ | ✓ | ✓ |
| intl | ✓ | ✓ | ✓ | ✓ |
| json | ✓ | ✓ | ✓ | ✓ |
| **ldap** | ✓ | ✓ | — | ✓ |
| libxml | ✓ | ✓ | ✓ | ✓ |
| **litespeed** | — | — | ✓ | ✓ |
| mbstring | ✓ | ✓ | ✓ | ✓ |
| memcached | ✓ | ✓ | ✓ | ✓ |
| msgpack | ✓ | ✓ | ✓ | ✓ |
| mysqli | ✓ | ✓ | ✓ | ✓ |
| mysqlnd | ✓ | ✓ | ✓ | ✓ |
| openssl | ✓ | ✓ | ✓ | ✓ |
| **pcntl** | — | — | ✓ | — |
| pcre | ✓ | ✓ | ✓ | ✓ |
| PDO | ✓ | ✓ | ✓ | ✓ |
| pdo_mysql | ✓ | ✓ | ✓ | ✓ |
| **pdo_pgsql** | ✓ | ✓ | — | ✓ |
| **pdo_sqlite** | ✓ | ✓ | — | ✓ |
| **pgsql** | ✓ | ✓ | — | ✓ |
| Phar | ✓ | ✓ | ✓ | ✓ |
| posix | ✓ | ✓ | ✓ | ✓ |
| random | ✓ | ✓ | ✓ | ✓ |
| readline | ✓ | ✓ | ✓ | ✓ |
| redis | ✓ | ✓ | ✓ | ✓ |
| Reflection | ✓ | ✓ | ✓ | ✓ |
| session | ✓ | ✓ | ✓ | ✓ |
| **shmop** | ✓ | ✓ | — | ✓ |
| SimpleXML | ✓ | ✓ | ✓ | ✓ |
| soap | ✓ | ✓ | ✓ | ✓ |
| sockets | ✓ | ✓ | ✓ | ✓ |
| sodium | ✓ | ✓ | ✓ | ✓ |
| SPL | ✓ | ✓ | ✓ | ✓ |
| **sqlite3** | ✓ | ✓ | — | ✓ |
| standard | ✓ | ✓ | ✓ | ✓ |
| sysvmsg | ✓ | ✓ | ✓ | ✓ |
| sysvsem | ✓ | ✓ | ✓ | ✓ |
| sysvshm | ✓ | ✓ | ✓ | ✓ |
| tokenizer | ✓ | ✓ | ✓ | ✓ |
| **uploadprogress** | ✓ | ✓ | — | ✓ |
| xml | ✓ | ✓ | ✓ | ✓ |
| xmlreader | ✓ | ✓ | ✓ | ✓ |
| **xmlrpc** | ✓ | ✓ | — | ✓ |
| xmlwriter | ✓ | ✓ | ✓ | ✓ |
| xsl | ✓ | ✓ | ✓ | ✓ |
| **yaml** | ✓ | ✓ | — | ✓ |
| Zend OPcache | ✓ | ✓ | ✓ | ✓ |
| zip | ✓ | ✓ | ✓ | ✓ |
| zlib | ✓ | ✓ | ✓ | ✓ |

Totals: nginx-fpm 66, apache-fpm 66, OLS v1.0.3 58, OLS + sury SAPI (prototype) 66

`cgi-fcgi` / `litespeed` are the SAPI modules themselves, not real differences.

## ini settings that differ

Only keys where fpm and either OLS column disagree; `cgi.*`, `fastcgi.*` and `fpm.*` (SAPI-specific)
left out. The prototype's `max_input_vars = 4321` is the deliberate `.ddev/php/` override test.

| ini setting | nginx/apache (fpm) | OLS v1.0.3 | OLS + sury SAPI |
|---|---|---|---|
| `apc.coredump_unmap` | `0` | *(not loaded)* | `0` |
| `apc.enable_cli` | `0` | *(not loaded)* | `0` |
| `apc.enabled` | `1` | *(not loaded)* | `1` |
| `apc.entries_hint` | `0` | *(not loaded)* | `0` |
| `apc.gc_ttl` | `3600` | *(not loaded)* | `3600` |
| `apc.mmap_hugepage_size` | `0` | *(not loaded)* | `0` |
| `apc.serializer` | `php` | *(not loaded)* | `php` |
| `apc.shm_size` | `32M` | *(not loaded)* | `32M` |
| `apc.slam_defense` | `0` | *(not loaded)* | `0` |
| `apc.smart` | `0` | *(not loaded)* | `0` |
| `apc.ttl` | `0` | *(not loaded)* | `0` |
| `apc.use_request_time` | `0` | *(not loaded)* | `0` |
| `date.timezone` | `Europe/Bratislava` | `UTC` | `Europe/Bratislava` |
| `extension_dir` | `/usr/lib/php/20240924` | `/usr/local/lsws/lsphp84/lib/php/20240924` | `/usr/lib/php/20240924` |
| `ffi.enable` | `preload` | *(not loaded)* | `preload` |
| `imagick.skip_version_check` | `1` | `0` | `1` |
| `include_path` | `.:/usr/share/php` | `.:` | `.:/usr/share/php` |
| `ldap.max_links` | `-1` | *(not loaded)* | `-1` |
| `max_input_vars` | `5000` | `5000` | `4321` |
| `memcached.serializer` | `igbinary` | `php` | `igbinary` |
| `msgpack.force_f32` | *(not loaded)* | `0` | *(not loaded)* |
| `opcache.jit` | *(empty)* | `disable` | *(empty)* |
| `pgsql.allow_persistent` | `1` | *(not loaded)* | `1` |
| `pgsql.auto_reset_persistent` | *(empty)* | *(not loaded)* | *(empty)* |
| `pgsql.ignore_notice` | `0` | *(not loaded)* | `0` |
| `pgsql.log_notice` | `0` | *(not loaded)* | `0` |
| `pgsql.max_links` | `-1` | *(not loaded)* | `-1` |
| `pgsql.max_persistent` | `-1` | *(not loaded)* | `-1` |
| `sqlite3.defensive` | `1` | *(not loaded)* | `1` |
| `uploadprogress.file.contents_template` | `/tmp/upload_contents_%s` | *(not loaded)* | `/tmp/upload_contents_%s` |
| `uploadprogress.file.filename_template` | `/tmp/upt_%s.txt` | *(not loaded)* | `/tmp/upt_%s.txt` |
| `uploadprogress.get_contents` | `0` | *(not loaded)* | `0` |
| `yaml.decode_binary` | `0` | *(not loaded)* | `0` |
| `yaml.decode_php` | `0` | *(not loaded)* | `0` |
| `yaml.decode_timestamp` | `0` | *(not loaded)* | `0` |
| `yaml.output_canonical` | `0` | *(not loaded)* | `0` |
| `yaml.output_indent` | `2` | *(not loaded)* | `2` |
| `yaml.output_width` | `80` | *(not loaded)* | `80` |
| `zend.assertions` | `1` | `-1` | `1` |

## Root causes

1. **Different PHP build and ini tree.** `Dockerfile.openlitespeed` installs LiteSpeed's
   `lsphp${V}` + a hand-picked list (`common mysql curl intl opcache` + `imagick redis igbinary
   memcached`), reading `/usr/local/lsws/lsphp84/etc/php/8.4/litespeed/` and
   `mods-available/`. Anything DDEV adds to its image (apcu, sqlite3/pdo_sqlite, pgsql, ldap,
   yaml, ffi, shmop, uploadprogress, xmlrpc, xdebug, xhprof …) is a separate Debian build lsphp
   never sees. LiteSpeed packages also bring their own defaults (`opcache.jit=disable`,
   `zend.assertions=-1`, `memcached.serializer=php`, `include_path=.:`) and extras DDEV doesn't
   load (enchant, gmp, pcntl).
2. **php.ini copied at build time.** DDEV's `/start.sh` edits php.ini **at container start**
   (`perl -pi … date.timezone … $(find /etc/php -name php.ini)`) and copies
   `/mnt/ddev_config/php/*.ini` into `cli/conf.d` and `fpm/conf.d` only. The build-time copy in
   the lsws tree misses both.
3. **`ddev xdebug` / `ddev xhprof` can't reach lsphp.** They run `phpenmod xdebug` (Debian
   `/etc/php/<v>/*/conf.d`, not the lsws tree) and, for `webserver_type: generic`,
   `supervisorctl restart 'webextradaemons:*'`.
4. **lsphp doesn't survive that restart** (even with fix 1). DDEV wraps every
   `web_extra_daemons` command in `bash -c '<cmd>; exit_code=$?; …'`, so supervisor's TERM hits
   bash, the old lsphp is orphaned and keeps `127.0.0.1:9000`; the new one fails
   (`webextradaemons:lsphp  BACKOFF  Exited too quickly`) and requests are still served by the
   old process with the old ini.

## Fixes

All verified in the throwaway project (columns "OLS + sury SAPI"): 66/66 extensions, identical
ini apart from SAPI keys, timezone, `.ddev/php` override, xdebug and xhprof on/off.

### 1. Use sury's LiteSpeed SAPI instead of LiteSpeed's lsphp (`web-build/Dockerfile.openlitespeed`)

```bash
V="${DDEV_PHP_VERSION}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "php${V}-litespeed"
ln -sf "/usr/bin/lsphp${V}" /usr/local/lsws/fcgi-bin/lsphp
```

- Exists for every DDEV PHP version (5.6–8.5) in the web image's sury repo, so the
  **bookworm sidecar can be removed** (`openlitespeed/lsphp-sidecar/`, `sync-lsphp-mode.sh`,
  the pre-start hook, `DDEV_LSPHP_MODE`) and 5.6/7.0–7.3 become available.
- Drop the LiteSpeed `lsphp${V}-*` packages; keep the LiteSpeed repo only for `openlitespeed`.
- Side effect: apt upgrades the image's `php${V}-*` together to the repo's current version
  (here 8.4.24 → 8.4.26, CLI/fpm/litespeed all consistent). Pinning to the image's version is
  usually impossible (sury keeps only the latest), so accept it.

### 2. Share DDEV's php.ini and conf.d with the litespeed SAPI (same Dockerfile)

```bash
rm -rf "/etc/php/${V}/litespeed/conf.d" "/etc/php/${V}/litespeed/php.ini"
ln -s ../fpm/conf.d  "/etc/php/${V}/litespeed/conf.d"
ln -s ../fpm/php.ini "/etc/php/${V}/litespeed/php.ini"
```

- `conf.d` symlink: DDEV's extension set, `.ddev/php/*.ini` (copied into `fpm/conf.d` by
  `start.sh`) and `phpenmod`/`phpdismod` (xdebug, xhprof) all apply to lsphp with no extra code.
- `php.ini` symlink: `start.sh`'s `perl -pi` replaces it with a regular file at start, but only
  after applying the same edits, so the content equals fpm's every start. (A copy made at
  start by the lsphp wrapper would work too.)
- Remove the build-time `cp /etc/php/${V}/fpm/php.ini …` and its `ponytail` note; README's
  "`.ddev/php/*.ini` overrides don't reach lsphp" and "`ddev xdebug on` does not drive lsphp"
  limitations go away.

### 3. Make the lsphp daemon restartable (`web-build/openlitespeed/ddev-openlitespeed-lsphp`)

```bash
#!/bin/bash
#ddev-generated
# A previous lsphp can survive `supervisorctl restart` (DDEV wraps daemons in bash -c);
# free 127.0.0.1:9000 first, and pass TERM on to lsphp ourselves.
pkill -TERM -x lsphp 2>/dev/null
for i in $(seq 1 50); do pgrep -x lsphp >/dev/null || break; sleep 0.1; done
pkill -KILL -x lsphp 2>/dev/null
PHP_LSAPI_CHILDREN="${OLS_LSAPI_CHILDREN:-10}" /usr/local/lsws/fcgi-bin/lsphp -b 127.0.0.1:9000 &
LSPHP_PID=$!
trap 'kill -TERM "${LSPHP_PID}" 2>/dev/null; wait "${LSPHP_PID}"; exit 0' TERM INT
wait "${LSPHP_PID}"
```

(The sidecar branch disappears with fix 1.) `ddev-openlitespeed-start` has the same orphan risk
for OLS itself; it already stops OLS in its TERM trap, which only fires if TERM reaches it —
worth the same pre-start cleanup (`lswsctrl stop` before `start`).

### 4. Tests (`tests/test.bats`)

Add assertions that fail on today's v1.0.3:

- loaded extensions over HTTP == `ddev exec php -m` minus SAPI modules;
- a `.ddev/php/zz-test.ini` value is visible over HTTP;
- `date.timezone` over HTTP == `ddev exec php -r 'echo ini_get("date.timezone");'`;
- `ddev xdebug on` → `xdebug.mode` non-empty over HTTP; `ddev xdebug off` → xdebug not loaded;
  same for `ddev xhprof`;
- `supervisorctl status` shows `webextradaemons:lsphp RUNNING` after those toggles.

## Not covered

- LSCache / `.htaccess` behaviour, OLS vs LiteSpeed Enterprise differences.
- Database, Mailpit delivery end to end (only `sendmail_path` compared).
- Non-8.4 PHP versions were checked for package availability only, not run.
