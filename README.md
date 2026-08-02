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
- **LSCache** advertised to the [LiteSpeed Cache](https://wordpress.org/plugins/litespeed-cache/)
  plugin (`X-LSCACHE`), so the plugin detects the server and can drive page caching.
- PHP version follows DDEV (`ddev config --php-version=… && ddev restart`) with
  automatic switching between native and sidecar lsphp — see below.
- Project `.htaccess` is honoured for front-controller rewrites (WordPress, Drupal,
  Laravel, …), like apache-fpm.
- OLS logs stream to `ddev logs -f`.

## Install

```bash
ddev add-on get morvy/ddev-openlitespeed
ddev restart
```

## PHP versions

Available: **7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5**. Set one with
`ddev config --php-version=<version> && ddev restart`.

8.1–8.5 run lsphp natively in the web container; 7.4 and 8.0 run it in a
Debian-bookworm sidecar container. PHP 5.6 and 7.0–7.3 are not available.

## How it works

Inside the `web` container, two supervised daemons run as the project's (non-root,
code-owning) user:

| Piece | Role |
|-------|------|
| `config.openlitespeed.yaml` | sets `webserver_type: generic`; a `pre-start` hook chooses native/sidecar; runs the **lsphp** and **openlitespeed** daemons; exposes 80/443 through `ddev-router` |
| `openlitespeed/sync-lsphp-mode.sh` | pre-start host hook: picks native vs sidecar for the current PHP version and generates the sidecar `docker-compose` file when needed |
| `openlitespeed/lsphp-sidecar/Dockerfile` | the bookworm lsphp sidecar image (7.4/8.0), built automatically on `ddev start` |
| `web-build/Dockerfile.openlitespeed` | installs OpenLiteSpeed; installs `lsphp${DDEV_PHP_VERSION//./}` natively when trixie has it, else records "sidecar" mode |
| `web-build/openlitespeed/httpd_config.conf` | main OLS config: one vhost, lsphp external app (`autoStart 0`), LSCache module, `:80` (router) + `:443` (DDEV master cert) listeners |
| `web-build/openlitespeed/vhost.conf` | vhost template; docroot injected at start; rewrites `X-Forwarded-Proto` into real HTTPS server vars |
| `web-build/openlitespeed/ddev-openlitespeed-start` | foreground OLS wrapper: renders the vhost, points OLS at the active lsphp, streams logs |

Request flow: `ddev-router` terminates public TLS and forwards **plain HTTP to OLS on
:80** (with `X-Forwarded-Proto`); OLS restores the HTTPS server vars and proxies PHP
over LSAPI to the active lsphp (local `127.0.0.1:9000`, or `openlitespeed-lsphp:9000`
in the sidecar).

> **Why lsphp is a separate process:** this OLS build has no working suEXEC/cgid helper,
> so OLS cannot fork lsphp itself (`cgidSuEXEC failed`). lsphp runs as its own daemon and
> the external app uses `autoStart 0` (connect-only). That also makes the bookworm sidecar
> for EOL PHP straightforward — OLS just connects to it over TCP.

## Known limitations

- **No WebAdmin console.** OpenLiteSpeed's admin console runs its own PHP as an internal
  worker that needs the same (broken) suEXEC helper, so it can't run in this container.
  It's disabled; configure OpenLiteSpeed by editing the files under
  `.ddev/web-build/openlitespeed/` and running `ddev restart`.
- **`ddev xdebug on` does not drive lsphp yet** (lsphp uses its own ini directory).
- **`.ddev/php/*.ini` overrides don't reach lsphp** (only the base `php.ini` is copied, and
  only in native mode).
- **Sidecar mode (7.4/8.0) bind-mounts the code**, so it can be slower on macOS/Windows
  than native PHP — expected for legacy versions.

## Uninstall

```bash
ddev add-on remove openlitespeed
ddev restart
```

Removes the `#ddev-generated` files (and the generated sidecar compose) and reverts
`webserver_type` to your project's previous value.

## Releasing

Push a version tag; the `release` workflow runs the full PHP matrix against it and
publishes a GitHub release only if every job passes:

```bash
git tag v1.0.2
git push origin v1.0.2
```

## License

MIT — see [LICENSE](LICENSE).
