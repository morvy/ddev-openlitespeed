#ddev-generated
# lsphp sidecar for PHP versions that Debian trixie (the DDEV web image) no
# longer ships — currently 7.4 and 8.0, which LiteSpeed still packages for
# Debian bookworm. Runs lsphp as an LSAPI server; the web container's
# OpenLiteSpeed connects to it over the DDEV network. Only used for those EOL
# versions, so modern PHP keeps running natively in the web container (no
# code-mount sidecar => no macOS/Windows slowdown).
FROM debian:bookworm-slim
ARG DDEV_PHP_VERSION=8.0

SHELL ["/bin/bash", "-c"]
RUN <<'EOF'
set -euo pipefail
LSPHPVER="${DDEV_PHP_VERSION//./}"   # 8.0 -> 80
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends wget ca-certificates

# LiteSpeed bookworm repo + signing keys. Done deterministically with wget:
# repo.litespeed.sh fetches its keys with curl, which isn't in bookworm-slim.
wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg https://rpms.litespeedtech.com/debian/lst_debian_repo.gpg
wget -qO /etc/apt/trusted.gpg.d/lst_repo.gpg https://rpms.litespeedtech.com/debian/lst_repo.gpg
echo "deb http://rpms.litespeedtech.com/debian/ bookworm main" > /etc/apt/sources.list.d/lst_debian_repo.list
apt-get update

if ! apt-cache show "lsphp${LSPHPVER}" >/dev/null 2>&1; then
  echo "ERROR: no lsphp package for PHP ${DDEV_PHP_VERSION} in the LiteSpeed bookworm repo." >&2
  exit 1
fi

apt-get install -y --no-install-recommends \
  "lsphp${LSPHPVER}" \
  "lsphp${LSPHPVER}-common" \
  "lsphp${LSPHPVER}-mysql" \
  "lsphp${LSPHPVER}-curl" \
  "lsphp${LSPHPVER}-intl" \
  "lsphp${LSPHPVER}-opcache"
for ext in imagick redis igbinary memcached; do
  apt-get install -y --no-install-recommends "lsphp${LSPHPVER}-${ext}" \
    || echo "NOTE: lsphp${LSPHPVER}-${ext} not available for PHP ${DDEV_PHP_VERSION}, skipping."
done

ln -sf "/usr/local/lsws/lsphp${LSPHPVER}/bin/lsphp" /usr/local/bin/lsphp
rm -rf /var/lib/apt/lists/*
EOF

EXPOSE 9000
ENV PHP_LSAPI_CHILDREN=10
# LSAPI server on all interfaces so the web container's OLS can reach it.
CMD ["/usr/local/bin/lsphp", "-b", "0.0.0.0:9000"]
