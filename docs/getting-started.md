  ![GettingStarted](images/gettingstarted.png)

This guide walks through the initial RTProxy deployment step by step, from preparing the server to publishing the first HTTPS service.

## 1. Before You Start

Prepare the following before running the installer:

- A clean Debian 12 or Ubuntu 22.04+ server
- Two Ethernet interfaces
- Root or sudo access
- Outbound internet connectivity
- A domain already managed in Cloudflare
- A service you want to publish, such as Grafana, NetBox, Proxmox, or another internal web application

Recommended network model:

| Interface | Role |
|---|---|
| eth0 | Ingress / client-facing interface |
| eth1 | Backend / internal service interface |

## 2. Download the Repository

Clone the project and move into the repository directory:

```bash
git clone https://github.com/lucabiancorosso/rtproxy.git
cd rtproxy
```

If you downloaded a ZIP instead, extract it and enter the project folder before continuing.

## 3. Review the Installer

Make sure the installer script is present:

```bash
ls -l install-rtproxy.sh
```

Expected result: the file exists in the repository root.

## 4. Run the Installer

Start the installation:

```bash
sudo bash install-rtproxy.sh
```

The installer is intended for a **clean server** and will install and configure Nginx automatically.

## 5. Follow the Installer Prompts

During installation, be prepared to provide:

- Email address for ACME / Let's Encrypt registration
- The ingress interface used for client-facing traffic
- Certificate mode, depending on how your services are exposed
- Certificate authority environment, typically staging for testing or production for live use
- Cloudflare API Key

If you are using internal-only services, DNS validation through Cloudflare is the recommended option.

Here is a an installation screenshot
  ![Install](images/install.png)

## 6. Choose Staging or Production

RTProxy may offer a choice between **Let's Encrypt staging** and **Let's Encrypt production**.

### Staging

Use staging when:

- You are testing RTProxy for the first time
- You are validating Cloudflare token permissions
- You want to verify DNS-01 automation
- You want to avoid Let's Encrypt production rate limits while testing

Important notes:

- Staging certificates are **not trusted by browsers**
- Browser warnings are expected
- This mode is only for validation and dry runs

### Production

Use production when:

- DNS validation is working correctly
- You are ready to expose the service for real use
- You need a publicly trusted certificate

Important notes:

- Production certificates are trusted by browsers
- Let's Encrypt rate limits apply
- This is the correct mode for live services

Recommended workflow:

1. Test the full process in staging
2. Confirm certificate issuance works
3. Re-run or switch to production for the final trusted certificate

## 7. Verify the Installation

After installation, validate the basic platform state.

Check Nginx:

```bash
systemctl status nginx
```

Check the generated runtime configuration:

```bash
nginx -t
```

Check the RTProxy CLI is available:

```bash
rtproxy
```

Check the current published services:

```bash
rtproxy list
```

If this is a fresh installation, the list may be empty.

## 8. Publish Your First Service

Example:

```bash
rtproxy add grafana.example.com http://10.10.0.5:3000
```

This command should:

1. Request a certificate
2. Create the Nginx site configuration
3. Install certificate files
4. Reload Nginx
5. Expose the service via HTTPS

Expected final URL:

```text
https://grafana.example.com
```


## 9. Validate the Published Service

After adding the service, verify:

- The DNS record resolves to the RTProxy ingress IP
- Nginx is listening correctly
- The backend service is reachable from RTProxy
- HTTPS opens successfully in a browser

Useful checks:

```bash
rtproxy list
systemctl status nginx
nginx -t
tail -f /var/log/rtproxy.log
```

## 10. Backend Service Considerations

For HTTP backends:

```text
rtproxy add app.example.com http://10.10.0.5:8080
```

For HTTPS backends:

```text
rtproxy add proxmox.example.com https://10.10.0.10:8006
```

RTProxy is intended to support internal HTTPS services, including self-signed backends.

## 11. Renewal Operations

Renewal is handled through:

```bash
rtproxy renew-all
```

Recommended cron entry:

```text
0 2 * * * root rtproxy renew-all
```

It is good practice to test renewal manually before relying on automation.

## 12. Logs and Troubleshooting

Logs:

```text
/var/log/rtproxy.log
/var/log/rtproxy-check.log
/var/log/rtproxy-install.log
```

Basic troubleshooting commands:

```bash
nginx -t
systemctl status nginx
tail -f /var/log/rtproxy.log
```

## 13. Recommended First Deployment Flow

A practical first-run process is:

1. Prepare a clean server
2. Confirm both network interfaces are present
3. Ensure the domain is managed in Cloudflare
4. Create the Cloudflare API token
5. Start in Let's Encrypt staging mode
6. Validate DNS-01 certificate issuance
7. Add the first test service
8. Confirm HTTPS access
9. Switch to production mode for the final deployment

## 14. Related Documentation

- [README](../README.md)
- [Cloudflare DNS-01 Guide](cloudflare.md)
