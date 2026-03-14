# RTProxy by Luca Biancorosso

![Architecture](images/rt-logo.png)

Self-contained installer for a lightweight Nginx reverse proxy with automatic TLS management using acme.sh

---

## RTProxy -- Lightweight Automated Reverse Proxy with TLS

RTProxy is a **lightweight reverse proxy automation framework** designed to quickly publish internal services over HTTPS with minimal operational effort.

It combines:

- **Nginx** (reverse proxy engine)
- **acme.sh** (ACME client for TLS certificates)
- **Let's Encrypt** (certificate authority)
- **Cloudflare DNS-01 validation**
- A simple **CLI management tool (`rtproxy`)**

RTProxy is intended for environments where you want **secure HTTPS publishing without the complexity of full ingress controllers such as Traefik or Kubernetes ingress**.

---

## Key Design Goals

RTProxy was designed with the following priorities:

- Minimal operational complexity
- Fully automated certificate lifecycle
- CLI-based management with no manual Nginx editing
- Support for **internal and external services**
- Easy deployment on **clean Linux servers**
- Minimal dependencies
- Secure by default

---

## High-Level Architecture

![Architecture](images/RT-Proxy.jpg)

RTProxy performs:

- TLS certificate issuance
- Nginx configuration generation
- HTTPS redirect configuration
- Automatic certificate renewal

---

## Performance Architecture

For **maximum performance and network isolation**, RTProxy requires **two Ethernet interfaces**.

This design separates client access from backend services.

Benefits:

- Improved packet processing efficiency
- Separation of security zones
- Easier firewall policy control
- Reduced contention between ingress and backend traffic
- Higher performance under load
- Zero-trust principle

---

## Requirements

### Supported OS

- Debian 12+ (**preferred OS**)
- Ubuntu 22.04+
- Minimal Linux server installation

### Hardware Requirements

Minimum:

- 2 CPU cores
- 2 GB RAM
- 10 GB disk

Recommended:

- 4 CPU cores
- 4 GB RAM

### Network Requirements

RTProxy **requires two Ethernet interfaces**:

| Interface | Purpose |
|---|---|
| eth0 | Public ingress interface |
| eth1 | Internal service network |

This separation provides **maximum performance and cleaner architecture**.

### Other Requirements

- Root access
- Outbound internet connectivity
- DNS control for the domains used
- Cloudflare account for DNS validation

---

## Components Installed

The installer automatically installs and configures the following components.

| Component | Description |
|---|---|
| Nginx | Reverse proxy engine |
| acme.sh | ACME certificate management |
| rtproxy CLI | Management tool |
| Nginx configuration | Automatic reverse proxy definitions |
| Certificate storage | TLS certificate management |

---

## Installation

Run the installer:

```bash
sudo bash install-rtproxy.sh
```

The installer performs:

1. Dependency installation
2. Nginx installation and configuration
3. acme.sh installation
4. CLI tool installation
5. Directory structure creation
6. Logging configuration
7. TLS configuration

For a full walkthrough, screenshots, first-run guidance, and validation steps, see the [Getting Started Guide](docs/getting-started.md).

---

## Directory Layout

```text
/etc/rtproxy/
    config.env

/etc/nginx/rtproxy/
    sites/

/etc/nginx/ssl/
    certificates

/var/www/rtproxy/
    ACME challenges

/opt/acme.sh/
    ACME client

/usr/local/bin/rtproxy
/usr/local/sbin/rtproxy
```

---

## CLI Usage

Main command:

```bash
rtproxy
```

### Add a Service

```text
rtproxy add <fqdn> <backend>
```

Example:

```text
rtproxy add grafana.example.com http://10.10.0.5:3000
```

RTProxy automatically:

1. Requests a TLS certificate
2. Installs the certificate
3. Generates Nginx configuration
4. Reloads Nginx

Result:

```text
https://grafana.example.com
```

### Add HTTPS Backend

```text
rtproxy add proxmox.example.com https://10.10.0.10:8006
```

RTProxy automatically disables backend certificate validation for internal services.

### Remove Service

```text
rtproxy remove <fqdn>
```

Example:

```text
rtproxy remove grafana.example.com
```

Removes:

- Nginx configuration
- Certificate files
- ACME entries

### List Services

```text
rtproxy list
```

Example output:

```text
grafana.example.com
proxmox.example.com
netbox.example.com
```

### Certificate Renewal

Certificates are renewed using:

```text
rtproxy renew-all
```

Internally executes:

```text
acme.sh --cron
```

Recommended cron:

```text
0 2 * * * root rtproxy renew-all
```

---

## Configuration

Main configuration file:

```text
/etc/rtproxy/config.env
```

Example:

```text
MODE="internal"
INGRESS_IF="eth0"
BACKEND_IF="eth1"
LE_EMAIL="admin@example.com"
WEBROOT="/var/www/rtproxy"
ACME_HOME="/opt/acme.sh"
ACME_SERVER="letsencrypt"
WARN_DAYS="14"
CRIT_DAYS="7"
```

For the full DNS setup and ACME guidance, see the [Cloudflare DNS-01 Guide](docs/cloudflare.md).

---

## Security Model

RTProxy follows several security best practices:

- HTTPS enforced automatically
- TLS private keys stored with restricted permissions
- Backend networks isolated from public ingress
- Minimal software footprint
- No web UI attack surface

Key permissions:

```text
chmod 600 private keys
chmod 644 certificates
chmod 600 config.env
```

---

## Example Use Cases

RTProxy is ideal for publishing internal services such as:

- Grafana
- NetBox
- AWX
- Rundeck
- Proxmox
- NAS interfaces
- Monitoring dashboards

It works especially well for:

- Homelabs
- Infrastructure management portals
- DevOps environments
- Internal tooling

---

## Comparison

| Feature | RTProxy | Traefik | Caddy |
|---|---|---|---|
| Complexity | Low | Medium | Low |
| Automation | Yes | Yes | Yes |
| Operational footprint | Very small | Medium | Medium |
| Kubernetes integration | No | Yes | No |
| CLI management | Yes | Limited | No |

RTProxy is intended for **simple infrastructure publishing scenarios** rather than large orchestrated environments.

---

## Logging

Logs are stored in:

```text
/var/log/rtproxy.log
/var/log/rtproxy-check.log
/var/log/rtproxy-install.log
```

Example:

```text
tail -f /var/log/rtproxy.log
```

---

## Troubleshooting

Check Nginx configuration:

```text
nginx -t
```

Check Nginx status:

```text
systemctl status nginx
```

Check ACME configuration:

```text
/opt/acme.sh/
```

For a step-by-step first deployment workflow, see the [Getting Started Guide](docs/getting-started.md).

---

## Documentation

- [Getting Started Guide](docs/getting-started.md)
- [Cloudflare DNS-01 Guide](docs/cloudflare.md)

---

## Roadmap

Future improvements may include:

- Multi-node cluster support
- Additional DNS providers
- Wildcard certificate support
- Backend health checks
- Prometheus metrics
- Rate limiting
- Authentication layer
- High availability mode

---

## License

MIT License

---

## Author

Luca Biancorosso
