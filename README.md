# ddev-openlitespeed

Replaces DDEV's default web server (nginx/apache-fpm) with **OpenLiteSpeed** running
**lsphp** (the LiteSpeed SAPI PHP), so you can develop and test against a real
OpenLiteSpeed stack locally.

Built on DDEV's `webserver_type: generic` mechanism (DDEV v1.24.3+), the same one
the official [`ddev-frankenphp`](https://github.com/ddev/ddev-frankenphp) add-on uses.

## What you get

- OpenLiteSpeed serving your project over the normal `https://<project>.ddev.site` URL.
- **lsphp** as the PHP runtime (real LiteSpeed SAPI, not php-fpm behind a proxy).
- **Correct HTTPS for PHP** behind the DDEV router: `$_SERVER['HTTPS']`, `SERVER_PORT`
  and `REQUEST_SCHEME` reflect the real scheme, so `is_ssl()` / `isSecure()`, redirects
  and absolute-URL generation work (no mixed-content or redirect loops).
- PHP version follows DDEV: `ddev config --php-version=8.3 && ddev restart` installs
  the matching `lsphp83`. Nothing is hardcoded — the lsphp version is derived from
  `DDEV_PHP_VERSION` at build time (`8.3` → `83`).
- The OpenLiteSpeed **WebAdmin console** at `https://<project>.ddev.site:7080`
  (login `admin` / `admin`).
- Project `.htaccess` is honoured for front-controller rewrites (WordPress, Drupal,
  Laravel, …), like apache-fpm.
- OLS logs stream to `ddev logs -f`.

## Install

```bash
ddev add-on get morvy/ddev-openlitespeed
ddev restart
```

Supported PHP versions: **7.4, 8.0–8.4** (the versions lsphp packages exist for).

## How it works

Two supervised daemons run inside the `web` container, both as the project's
(non-root, code-owning) user:

| Piece | Role |
|-------|------|
| `config.openlitespeed.yaml` | sets `webserver_type: generic`; runs two `web_extra_daemons` — **lsphp** on `127.0.0.1:9000`, then **openlitespeed** — and exposes ports 80/443 (+7080 admin) through `ddev-router` |
| `web-build/Dockerfile.openlitespeed` | installs OpenLiteSpeed + `lsphp${DDEV_PHP_VERSION//./}`; points a stable `fcgi-bin/lsphp` symlink at the chosen version; makes OLS's runtime dirs writable by the container user |
| `web-build/openlitespeed/httpd_config.conf` | main OLS config: one vhost, an lsphp external app with **`autoStart 0`** (connect to the running lsphp, never fork it), `:80` (router) + `:443` (DDEV master cert) listeners |
| `web-build/openlitespeed/vhost.conf` | vhost template; docroot injected at container start; rewrites `X-Forwarded-Proto` into real HTTPS server vars |
| `web-build/openlitespeed/ddev-openlitespeed-start` | foreground supervisor wrapper: renders the vhost, pins OLS's user/group to the runtime user, starts OLS, streams logs, restarts on exit |

Request flow: `ddev-router` terminates the public TLS and forwards **plain HTTP to
OLS on :80** (with `X-Forwarded-Proto`); OLS restores the HTTPS server vars for PHP,
then proxies PHP over LSAPI to the standalone **lsphp** daemon on `127.0.0.1:9000`.

> **Why lsphp is a separate daemon:** this apt build of OpenLiteSpeed has no working
> suEXEC/cgid helper, so OLS cannot fork external apps itself (`cgidSuEXEC failed`).
> Running lsphp as its own supervised process — and setting the external app to
> `autoStart 0` so OLS only connects to it — sidesteps that entirely and keeps PHP
> running as the code-owning user (so files it writes have correct host ownership).

## Known limitations (v0)

- **`ddev xdebug on` does not drive lsphp yet.** lsphp uses its own ini directory,
  separate from DDEV's php-fpm, so DDEV's xdebug toggle has no effect here. Planned
  for a later version.
- **`.ddev/php/*.ini` overrides don't reach lsphp.** Only DDEV's base `php.ini` is
  copied into lsphp at build time.
- **WebAdmin changes are not persisted** across `ddev restart` (config is baked into
  the image). Edit the files in `.ddev/web-build/openlitespeed/` instead.

## Uninstall

```bash
ddev add-on remove openlitespeed
ddev restart
```

This removes the `#ddev-generated` files and reverts `webserver_type` to your
project's previous value.

## Releasing

Releases are gated on the test suite. Push a version tag and the `release`
workflow runs the full PHP matrix against that tag, then publishes a GitHub
release only if every job passes:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`ddev add-on get morvy/ddev-openlitespeed` installs the latest published release.

## License

MIT — see [LICENSE](LICENSE).
