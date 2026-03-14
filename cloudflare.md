# Cloudflare DNS-01 Guide

This guide explains how to configure Cloudflare so RTProxy can issue TLS certificates using **DNS-01 validation** through `acme.sh`.

## Why DNS-01 Matters

DNS-01 validation is the preferred option when:

- Services are internal only
- Port 80 cannot be opened from the internet
- You want certificates for management or lab platforms
- You want to preserve a private architecture

Examples:

```text
grafana.internal.example.com
proxmox.lab.example.com
netbox.mgmt.example.com
```

With DNS-01, Let's Encrypt verifies domain ownership by reading a temporary TXT record from DNS.

## 1. Create the Cloudflare API Token

Open the Cloudflare dashboard:

```text
https://dash.cloudflare.com/profile/api-tokens
```

Then select:

```text
Create Token
```

Choose:

```text
Custom Token
```

## 2. Required Token Permissions

Use the following permissions:

| Permission | Purpose |
|---|---|
| Zone → DNS → Edit | Create and remove ACME TXT records |
| Zone → Zone → Read | Discover zone configuration |

Example permission set:

```text
Zone.DNS:Edit
Zone.Zone:Read
```

## 3. Restrict the Token Scope

For security, scope the token to the specific zone used by RTProxy.

Example:

```text
example.com
```

Avoid using **All Zones** unless there is a strong operational need.

## 4. Configure RTProxy

If the key is hasn't been pass during the installation, it can be added manually following this step:

Edit:

```text
/etc/rtproxy/config.env
```

Add:

```text
DNS_PROVIDER="dns_cf"
CF_Token=YOUR_CLOUDFLARE_API_TOKEN
```

Example:

```text
DNS_PROVIDER="dns_cf"
CF_Token=xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Make sure the file is protected:

```bash
chmod 600 /etc/rtproxy/config.env
```

## 5. How Validation Works

During certificate issuance:

1. RTProxy requests a certificate through `acme.sh`
2. `acme.sh` creates a temporary TXT record in Cloudflare
3. Cloudflare publishes the TXT record
4. Let's Encrypt queries the TXT record
5. Domain ownership is validated
6. The certificate is issued
7. The TXT record is removed automatically

Typical TXT record:

```text
_acme-challenge.example.com
```

## 6. Manual Validation Test

To confirm the integration works:

```bash
acme.sh --issue \
  --dns dns_cf \
  -d test.example.com
```

During the validation process, a TXT record should appear:

```text
_acme-challenge.test.example.com
```

Check propagation with:

```bash
dig TXT _acme-challenge.test.example.com
```

## 7. Staging vs Production

### Let's Encrypt Staging

Use staging when:

- Testing RTProxy for the first time
- Confirming the Cloudflare token is correct
- Checking DNS propagation behavior
- Avoiding production rate limits during lab work

Important:

- Staging certificates are **not trusted by browsers**
- Browser warnings are expected
- This mode is only for testing

### Let's Encrypt Production

Use production when:

- DNS validation already works
- The service is ready for real users
- You need a trusted browser certificate

Important:

- Production certificates are trusted by browsers
- Let's Encrypt production rate limits apply

Recommended workflow:

1. Test in staging
2. Confirm everything works
3. Switch to production for the final deployment

## 8. Security Best Practices

- Use **API Tokens**, not the Global API Key
- Restrict the token to a single zone
- Store the token only on the RTProxy host
- Protect `/etc/rtproxy/config.env` with restrictive permissions
- Rotate the token periodically if used in long-lived environments

## 9. Common Problems

### Certificate issuance fails

Check:

- Cloudflare token permissions
- Token zone scope
- DNS record correctness
- Outbound connectivity from RTProxy
- Current ACME logs

### TXT record not found

Check propagation manually:

```bash
dig TXT _acme-challenge.example.com
```

### Browser warning after issuance

This usually means a **staging** certificate is being used instead of a production certificate.

## 10. Useful Commands

Check Nginx configuration:

```bash
nginx -t
```

Check Nginx service:

```bash
systemctl status nginx
```

Inspect RTProxy logs:

```bash
tail -f /var/log/rtproxy.log
```

## 11. Related Documentation

- [README](../README.md)
- [Getting Started Guide](getting-started.md)
