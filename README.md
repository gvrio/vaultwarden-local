# Vaultwarden (Local Docker Deployment)

Run a local instance of [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (an unofficial Bitwarden-compatible server) behind a [Caddy](https://caddyserver.com/) reverse proxy with automatic HTTPS, all via Docker Compose.

Caddy terminates TLS using an internally-generated, self-signed certificate and proxies traffic to the Vaultwarden container. The service is exposed only on `127.0.0.1`, so it is reachable from the host machine only, not the local network.

## Requirements

- Docker and Docker Compose (Docker Desktop or the Compose plugin)
- A Bitwarden-compatible client (browser extension, desktop app, or mobile app) pointed at this server

## Usage

1. Start the stack:

   ```sh
   docker compose up -d
   ```

2. Vaultwarden will be available at:

   ```
   https://localhost:2080
   ```

3. On first run, open the URL above in a browser and create your account via the web vault, or configure a Bitwarden client with `https://localhost:2080` as the server URL.

4. Stop the stack:

   ```sh
   docker compose down
   ```

Vault data is persisted in `./vw-data` on the host (ignored by git) and survives container restarts/recreation. Caddy's TLS assets persist in the `caddy_data` and `caddy_config` Docker volumes.

## Changing the domain or port

By default the server is served at `https://localhost:2080`. To use a different domain and/or port, update it in three places so Caddy, Vaultwarden, and the exposed port all agree:

1. **`Caddyfile`** — change the site address:

   ```
   your.domain:PORT {
       reverse_proxy vaultwarden:80
       tls internal
   }
   ```

2. **`compose.yaml`** — update Vaultwarden's `DOMAIN` env var to match:

   ```yaml
   environment:
     DOMAIN: "https://your.domain:PORT"
   ```

3. **`compose.yaml`** — update the Caddy service's port mapping:

   ```yaml
   ports:
     - "127.0.0.1:PORT:PORT"
   ```

After editing, restart the stack for changes to take effect:

```sh
docker compose down
docker compose up -d
```

If you use a custom domain (instead of `localhost`), add an entry for it in your OS's hosts file (e.g. `/etc/hosts` on macOS/Linux) pointing it at `127.0.0.1`, for example:

```
127.0.0.1   vault.local
```

Editing the hosts file requires elevated privileges.

- **macOS/Linux:**

  ```sh
  sudo nano /etc/hosts
  ```

- **Windows:** the hosts file is at `C:\Windows\System32\drivers\etc\hosts`. Open it with an editor running as Administrator, e.g. right-click Notepad → "Run as administrator", then open the file from within Notepad.

## Trusting Caddy's self-signed certificate

Caddy serves `https://localhost:2080` with a self-signed (internal) certificate, so browsers and Bitwarden clients will show a security warning until it's trusted. Adding it to your OS/browser trust store requires elevated (admin/sudo) privileges, and you'll be prompted for your password.

The simplest workaround: just accept the browser's security exception for `localhost:2080` (or the equivalent "proceed anyway" option in your Bitwarden client) instead of installing the certificate system-wide.

**Note:** `tls internal` generates the certificate's SAN based on the domain in the `Caddyfile`. If you switch domains (e.g. from `localhost` to `vault.local`), Caddy issues a new certificate for the new domain — you'll need to re-accept the security exception (or re-trust the CA) again, even if you'd already trusted it for the old domain.
