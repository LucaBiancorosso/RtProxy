#!/usr/bin/env bash
set -euo pipefail

# ---- Settings / paths ----
RT_DIR="/etc/rtproxy"
NGX_RT_DIR="/etc/nginx/rtproxy"
WEBROOT="/var/www/rtproxy"

ACME_HOME="/opt/acme.sh"          # git clone location
ACME_BIN="${ACME_HOME}/acme.sh"
ACME_CONFIG_HOME="/etc/acme.sh"   # state dir (accounts/certs)

CFG="${RT_DIR}/config.env"
CLI="/usr/local/sbin/rtproxy"
CLI_LINK="/usr/local/bin/rtproxy"

LOG_FILE="/var/log/rtproxy-install.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (sudo)."
    exit 1
  fi
}

apt_install() {
  log "Installing dependencies..."
  DEBIAN_FRONTEND=noninteractive apt-get update -y >>"${LOG_FILE}" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl git jq openssl nginx iproute2 locales dos2unix >>"${LOG_FILE}" 2>&1
}

fix_locale() {
  # Optional: reduces perl warnings on minimal installs
  log "Configuring locale (en_US.UTF-8)..."
  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
  locale-gen >>"${LOG_FILE}" 2>&1 || true
  update-locale LANG=en_US.UTF-8 >>"${LOG_FILE}" 2>&1 || true
}

select_ingress_ip() {
  log "Detecting interfaces and IPs..."
  mapfile -t CANDS < <(ip -o -4 addr show scope global | awk '{print $2" "$4}' | sed 's|/.*||')

  if [[ "${#CANDS[@]}" -eq 0 ]]; then
    echo "ERROR: No global IPv4 addresses found. Configure networking first."
    exit 1
  fi

  echo
  echo "Available interface/IP:"
  local i=1
  for c in "${CANDS[@]}"; do
    echo "  ${i}) ${c}"
    i=$((i+1))
  done

  echo
  read -rp "Select INGRESS (bind) interface/IP [1-${#CANDS[@]}]: " sel
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#CANDS[@]} )); then
    echo "ERROR: invalid selection."
    exit 1
  fi

  local picked="${CANDS[$((sel-1))]}"
  INGRESS_IF="$(awk '{print $1}' <<<"$picked")"
  INGRESS_IP="$(awk '{print $2}' <<<"$picked")"
  log "Selected ingress: ${INGRESS_IF} ${INGRESS_IP}"
}

select_mode() {
  echo
  echo "Choose certificate validation mode:"
  echo "  1) External (HTTP-01)  - requires inbound port 80 reachable"
  echo "  2) Internal (DNS-01)   - Cloudflare DNS challenge (recommended for internal/split DNS)"
  echo
  read -rp "Select mode [1-2]: " m
  case "$m" in
    1) MODE="external" ;;
    2) MODE="internal" ;;
    *) echo "ERROR: invalid mode." ; exit 1 ;;
  esac
  log "MODE=${MODE}"
}

select_ca() {
  echo
  echo "Choose ACME CA:"
  echo "  1) Let's Encrypt PRODUCTION (trusted)  ✅"
  echo "  2) Let's Encrypt STAGING (untrusted)   (testing only)"
  echo
  read -rp "Select CA [1-2]: " c
  case "$c" in
    1) ACME_SERVER="letsencrypt" ;;
    2) ACME_SERVER="letsencrypt_test" ;;
    *) echo "ERROR: invalid selection." ; exit 1 ;;
  esac
  log "ACME_SERVER=${ACME_SERVER}"
}

ask_email() {
  echo
  read -rp "ACME email (for account metadata; LE no longer sends expiry emails): " LE_EMAIL
  [[ -n "${LE_EMAIL}" ]] || { echo "ERROR: email cannot be empty."; exit 1; }
}

ask_thresholds() {
  echo
  read -rp "Cert WARN threshold days (default 14): " WARN_DAYS || true
  read -rp "Cert CRIT threshold days (default 7): " CRIT_DAYS || true
  WARN_DAYS="${WARN_DAYS:-14}"
  CRIT_DAYS="${CRIT_DAYS:-7}"
  if ! [[ "${WARN_DAYS}" =~ ^[0-9]+$ ]] || ! [[ "${CRIT_DAYS}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: thresholds must be integers."
    exit 1
  fi
  log "WARN_DAYS=${WARN_DAYS} CRIT_DAYS=${CRIT_DAYS}"
}

ask_cloudflare_if_needed() {
  if [[ "${MODE}" != "internal" ]]; then
    DNS_PROVIDER=""
    CF_TOKEN=""
    return
  fi

  echo
  echo "Internal mode uses Cloudflare DNS-01 via acme.sh (dns_cf)."
  echo "Token permissions: Zone:DNS:Edit + Zone:Zone:Read (scope to your zone)."
  echo

  DNS_PROVIDER="dns_cf"

  read -rsp "Enter Cloudflare API Token (input hidden): " CF_TOKEN
  echo

  [[ -n "${CF_TOKEN}" ]] || { echo "ERROR: CF_Token cannot be empty."; exit 1; }

  # Basic sanity check
  if (( ${#CF_TOKEN} < 20 )); then
    echo "WARNING: Token length seems too short (${#CF_TOKEN} chars)."
    read -rp "Continue anyway? (y/N): " ans
    [[ "${ans}" =~ ^[Yy]$ ]] || exit 1
  fi

  # Masked preview
  first="${CF_TOKEN:0:1}"
  last="${CF_TOKEN: -1}"
  masked_len=$(( ${#CF_TOKEN} - 2 ))

  if (( masked_len > 0 )); then
    stars="$(printf '%*s' "$masked_len" '' | tr ' ' '*')"
    echo "Token accepted: ${first}${stars}${last} (length: ${#CF_TOKEN})"
  else
    echo "Token accepted (length: ${#CF_TOKEN})"
  fi
}

install_acme_sh_portable() {
  log "Installing acme.sh (portable) into ${ACME_HOME} ..."
  mkdir -p "${ACME_CONFIG_HOME}"
  chmod 700 "${ACME_CONFIG_HOME}"

  rm -rf "${ACME_HOME}"
  git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "${ACME_HOME}" >>"${LOG_FILE}" 2>&1
  chmod +x "${ACME_BIN}"

  "${ACME_BIN}" --home "${ACME_HOME}" --config-home "${ACME_CONFIG_HOME}" \
    --set-default-ca --server "${ACME_SERVER}" >>"${LOG_FILE}" 2>&1 || true

  "${ACME_BIN}" --home "${ACME_HOME}" --config-home "${ACME_CONFIG_HOME}" \
    --register-account -m "${LE_EMAIL}" --server "${ACME_SERVER}" >>"${LOG_FILE}" 2>&1 || true

  log "acme.sh version: $("${ACME_BIN}" --home "${ACME_HOME}" --config-home "${ACME_CONFIG_HOME}" --version | tr '\n' ' ')"
}

write_config() {
  log "Writing config to ${CFG}"
  mkdir -p "${RT_DIR}"
  cat > "${CFG}" <<EOF
MODE="${MODE}"
INGRESS_IF="${INGRESS_IF}"
INGRESS_IP="${INGRESS_IP}"
LE_EMAIL="${LE_EMAIL}"
WEBROOT="${WEBROOT}"
ACME_HOME="${ACME_HOME}"
ACME_CONFIG_HOME="${ACME_CONFIG_HOME}"
DNS_PROVIDER="${DNS_PROVIDER}"
ACME_SERVER="${ACME_SERVER}"
WARN_DAYS="${WARN_DAYS}"
CRIT_DAYS="${CRIT_DAYS}"
EOF

  if [[ "${MODE}" == "internal" ]]; then
    echo "CF_Token=${CF_TOKEN}" >> "${CFG}"
  fi

  chmod 600 "${CFG}"
}

setup_nginx_layout() {
  log "Setting up nginx layout..."
  mkdir -p "${NGX_RT_DIR}/sites"
  mkdir -p "${WEBROOT}/.well-known/acme-challenge"
  chown -R www-data:www-data "${WEBROOT}"

  cat > "${NGX_RT_DIR}/rtproxy.conf" <<'NGXINCLUDE'
include /etc/nginx/rtproxy/sites/*.conf;
NGXINCLUDE

  local main="/etc/nginx/nginx.conf"
  if ! grep -q "include /etc/nginx/rtproxy/rtproxy.conf;" "${main}"; then
    sed -i '/http *{/a \    include /etc/nginx/rtproxy/rtproxy.conf;' "${main}"
  fi

  cat > "${NGX_RT_DIR}/sites/00-health.conf" <<EOF
server {
  listen ${INGRESS_IP}:80 default_server;
  server_name _;
  location /.well-known/acme-challenge/ { root ${WEBROOT}; }
  location / { return 200 "rtproxy alive\n"; add_header Content-Type text/plain; }
}
EOF

  nginx -t >>"${LOG_FILE}" 2>&1
  systemctl enable nginx >>"${LOG_FILE}" 2>&1
  systemctl restart nginx >>"${LOG_FILE}" 2>&1
}

setup_logs() {
  log "Setting up logs..."
  touch /var/log/rtproxy.log
  chown root:adm /var/log/rtproxy.log || true
  chmod 0640 /var/log/rtproxy.log || true

  touch /var/log/rtproxy-check.log
  chown root:adm /var/log/rtproxy-check.log || true
  chmod 0640 /var/log/rtproxy-check.log || true
}

install_cli() {
  log "Installing rtproxy CLI to ${CLI} and linking to ${CLI_LINK}"

  cat > "${CLI}" <<'RTPROXYCLI'
#!/usr/bin/env bash
set -euo pipefail

# Auto-sudo for convenience (this tool manages system files/services)
if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -n "$0" "$@" 2>/dev/null || exec sudo "$0" "$@"
fi

CFG="/etc/rtproxy/config.env"
LOG="/var/log/rtproxy.log"
CHECK_LOG="/var/log/rtproxy-check.log"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2; }
die(){ log "ERROR: $*"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

[[ -r "${CFG}" ]] || die "missing ${CFG}. Run installer first."
# shellcheck disable=SC1090
source "${CFG}"

NGX_SITES="/etc/nginx/rtproxy/sites"
ACME_BIN="${ACME_HOME}/acme.sh"

acme(){ "${ACME_BIN}" --home "${ACME_HOME}" --config-home "${ACME_CONFIG_HOME}" "$@"; }

export_cf_env() {
  # shellcheck disable=SC2046
  export $(grep -E '^CF_[A-Za-z0-9_]*=' "${CFG}" | xargs -d '\n' || true)
}

issue_cert_http() {
  local domain="$1"
  acme --set-default-ca --server "${ACME_SERVER}" >/dev/null
  acme --register-account -m "${LE_EMAIL}" --server "${ACME_SERVER}" >/dev/null || true
  acme --issue --webroot "${WEBROOT}" -d "${domain}" --server "${ACME_SERVER}"
}

issue_cert_cf_dns() {
  local domain="$1"
  export_cf_env
  acme --set-default-ca --server "${ACME_SERVER}" >/dev/null
  acme --register-account -m "${LE_EMAIL}" --server "${ACME_SERVER}" >/dev/null || true
  acme --issue --dns dns_cf -d "${domain}" --server "${ACME_SERVER}"
}

install_cert_to_nginx() {
  local domain="$1"
  local cert_dir="/etc/nginx/ssl/${domain}"
  mkdir -p "${cert_dir}"

  acme --install-cert -d "${domain}" \
    --key-file       "${cert_dir}/privkey.pem" \
    --fullchain-file "${cert_dir}/fullchain.pem" \
    --reloadcmd      "systemctl reload nginx"

  chmod 600 "${cert_dir}/privkey.pem"
  chmod 644 "${cert_dir}/fullchain.pem"
}

write_site() {
  local domain="$1"
  local upstream="$2"
  local file="${NGX_SITES}/${domain}.conf"

  local extra_tls=""
  if [[ "${upstream}" == https://* ]]; then
    # Many internal backends use self-signed certs
    extra_tls=$'    proxy_ssl_server_name on;\n    proxy_ssl_verify off;\n'
  fi

  cat > "${file}" <<EOF
# Managed by rtproxy. Do not edit manually.
server {
  listen ${INGRESS_IP}:80;
  server_name ${domain};

  location /.well-known/acme-challenge/ { root ${WEBROOT}; }
  location / { return 301 https://\$host\$request_uri; }
}

server {
  listen ${INGRESS_IP}:443 ssl http2;
  server_name ${domain};

  ssl_certificate     /etc/nginx/ssl/${domain}/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/${domain}/privkey.pem;

  location / {
    proxy_pass ${upstream};
    proxy_http_version 1.1;
${extra_tls}    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF
}

nginx_check_reload() { nginx -t && systemctl reload nginx; }

cmd_add() {
  need nginx
  [[ $# -ge 2 ]] || die "Usage: rtproxy add <fqdn> <upstream_url>"
  local domain="$1"
  local upstream="$2"

  mkdir -p "${NGX_SITES}" /etc/nginx/ssl
  log "ADD ${domain} -> ${upstream}"

  # Issue cert FIRST (prevents nginx -t failing due to missing PEM)
  if [[ "${MODE}" == "external" ]]; then
    issue_cert_http "${domain}" | tee -a "$LOG"
  else
    issue_cert_cf_dns "${domain}" | tee -a "$LOG"
  fi

  install_cert_to_nginx "${domain}" | tee -a "$LOG"
  write_site "${domain}" "${upstream}"
  nginx_check_reload | tee -a "$LOG"

  log "OK https://${domain} -> ${upstream}"
}

cmd_remove() {
  need nginx
  [[ $# -ge 1 ]] || die "Usage: rtproxy remove <fqdn> [--revoke]"
  local domain="$1"; shift || true

  local do_revoke=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --revoke) do_revoke=1 ;;
      *) die "Unknown option: $1 (supported: --revoke)" ;;
    esac
    shift || true
  done

  log "REMOVE ${domain} (revoke=${do_revoke})"

  rm -f "${NGX_SITES}/${domain}.conf"
  rm -rf "/etc/nginx/ssl/${domain}"
  nginx_check_reload || true

  if [[ "${do_revoke}" -eq 1 ]]; then
    log "Revoking certificate at CA for ${domain}..."
    acme --revoke -d "${domain}" >/dev/null 2>&1 || true
  fi

  acme --remove -d "${domain}" >/dev/null 2>&1 || true

  log "OK removed ${domain}"
}

cmd_purge() {
  [[ $# -ge 1 ]] || die "Usage: rtproxy purge <fqdn>"
  cmd_remove "$1" --revoke
}

cmd_list() { ls -1 "${NGX_SITES}" 2>/dev/null | sed 's/\.conf$//' | grep -v '^00-health$' || true; }

cmd_status() {
  echo "MODE=${MODE}"
  echo "INGRESS_IP=${INGRESS_IP}"
  echo "ACME_SERVER=${ACME_SERVER}"
  echo "ACME_HOME=${ACME_HOME}"
  echo "ACME_CONFIG_HOME=${ACME_CONFIG_HOME}"
  echo "WARN_DAYS=${WARN_DAYS:-14}"
  echo "CRIT_DAYS=${CRIT_DAYS:-7}"
  echo
  systemctl --no-pager --full status nginx || true
}

cmd_renew_all() {
  log "RENEW cron"
  acme --cron | tee -a "$LOG" || true
  systemctl reload nginx || true
  log "OK renew-all attempted"
}

cmd_check() {
  need openssl
  need date
  local ssl_root="/etc/nginx/ssl"
  local warn_days="${WARN_DAYS:-14}"
  local crit_days="${CRIT_DAYS:-7}"
  local rc=0

  mkdir -p "$(dirname "$CHECK_LOG")"
  touch "$CHECK_LOG"

  {
    echo "[$(date '+%F %T')] CHECK starting (warn=${warn_days}d crit=${crit_days}d)"
    [[ -d "$ssl_root" ]] || { echo "No cert directory: $ssl_root"; exit 0; }

    shopt -s nullglob
    for d in "$ssl_root"/*; do
      [[ -d "$d" ]] || continue
      local domain pem not_after exp_epoch now_epoch days_left
      domain="$(basename "$d")"
      pem="$d/fullchain.pem"
      [[ -f "$pem" ]] || continue

      not_after="$(openssl x509 -in "$pem" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
      [[ -n "$not_after" ]] || { echo "WARN  ${domain}: cannot parse enddate"; (( rc < 1 )) && rc=1; continue; }

      exp_epoch="$(date -d "$not_after" +%s 2>/dev/null || true)"
      now_epoch="$(date +%s)"
      [[ -n "$exp_epoch" ]] || { echo "WARN  ${domain}: cannot parse date"; (( rc < 1 )) && rc=1; continue; }

      days_left=$(( (exp_epoch - now_epoch) / 86400 ))

      if (( days_left <= crit_days )); then
        echo "CRIT  ${domain}: ${days_left} days left (expires: ${not_after})"
        rc=2
      elif (( days_left <= warn_days )); then
        echo "WARN  ${domain}: ${days_left} days left (expires: ${not_after})"
        (( rc < 1 )) && rc=1
      else
        echo "OK    ${domain}: ${days_left} days left (expires: ${not_after})"
      fi
    done
    echo "[$(date '+%F %T')] CHECK done rc=${rc}"
  } | tee -a "$CHECK_LOG"

  exit "$rc"
}

cmd_debug() { set -x; cmd_status; }

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  remove) shift; cmd_remove "$@" ;;
  purge) shift; cmd_purge "$@" ;;
  list) cmd_list ;;
  status) cmd_status ;;
  renew-all) cmd_renew_all ;;
  check) cmd_check ;;
  debug) cmd_debug ;;
  *)
    cat <<USAGE
rtproxy - hybrid reverse proxy manager (nginx + acme.sh)

Commands:
  rtproxy add <fqdn> <upstream_url>
  rtproxy remove <fqdn> [--revoke]
  rtproxy purge <fqdn>               (remove + revoke)
  rtproxy list
  rtproxy status
  rtproxy renew-all
  rtproxy check
  rtproxy debug

Logs:
  /var/log/rtproxy.log
  /var/log/rtproxy-check.log

Note:
  Let's Encrypt no longer sends expiry emails; use 'rtproxy check' + timer.
USAGE
    exit 1
    ;;
esac
RTPROXYCLI

  chmod 755 "${CLI}"
  ln -sf "${CLI}" "${CLI_LINK}"
  dos2unix "${CLI}" >>"${LOG_FILE}" 2>&1 || true
}

setup_renew_timer() {
  log "Setting up renewal timer..."
  cat > /etc/systemd/system/rtproxy-renew.service <<EOF
[Unit]
Description=rtproxy certificate renewal (acme.sh cron)

[Service]
Type=oneshot
ExecStart=${CLI} renew-all
EOF

  cat > /etc/systemd/system/rtproxy-renew.timer <<'EOF'
[Unit]
Description=Daily rtproxy renewal (acme.sh cron)

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload >>"${LOG_FILE}" 2>&1
  systemctl enable --now rtproxy-renew.timer >>"${LOG_FILE}" 2>&1
}

setup_check_timer() {
  log "Setting up expiry check timer..."
  cat > /etc/systemd/system/rtproxy-check.service <<EOF
[Unit]
Description=rtproxy certificate expiry check

[Service]
Type=oneshot
ExecStart=${CLI} check
EOF

  cat > /etc/systemd/system/rtproxy-check.timer <<'EOF'
[Unit]
Description=Daily rtproxy certificate expiry check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=45m

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload >>"${LOG_FILE}" 2>&1
  systemctl enable --now rtproxy-check.timer >>"${LOG_FILE}" 2>&1
}

main() {
  require_root
  log "rtproxy installer (single-node) starting"

  apt_install
  fix_locale
  select_ingress_ip
  select_mode
  select_ca
  ask_email
  ask_thresholds
  ask_cloudflare_if_needed

  install_acme_sh_portable
  write_config
  setup_nginx_layout
  setup_logs
  install_cli
  setup_renew_timer
  setup_check_timer

  log "Installed."
  log "Config: ${CFG}"
  log "Try: rtproxy add <fqdn> <upstream_url>"
}

main "$@"