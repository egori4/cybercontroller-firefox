# CyberController Firefox

A small Docker Compose deployment for running a browser directly on a CyberController lab host.

The browser is exposed through a web UI and can save downloaded files directly into selected CyberController storage directories. This is useful when a file must be downloaded from the Internet from the CyberController itself rather than transferred from another workstation.

> **Unofficial lab utility.** This repository is not a Radware-supported CyberController component. Review it before using it outside a lab environment.

## What it deploys

The deployment uses the LinuxServer.io Firefox image:

```
lscr.io/linuxserver/firefox:latest
```

Default access:

```
https://<CyberController-IP>:3010
```

The Firefox web UI uses HTTPS on container port `3001`. A self-signed certificate is expected, so the browser connecting to the web UI may display a certificate warning.

Authentication is enabled through `CUSTOM_USER` and `PASSWORD`.

## Download mappings

Inside Firefox, the following directories appear under `Downloads`:

| Firefox path | CyberController host path |
|---|---|
| `/config/Downloads/upload-temp` | `/opt/radware/storage/uploads/temp` |
| `/config/Downloads/maintenance` | `/opt/radware/storage/maintenance/browser-downloads` |

Note the CyberController path is **`uploads/temp`**, plural `uploads`.

The deployment deliberately does not make the entire maintenance directory writable by Firefox. It creates:

```
/opt/radware/storage/maintenance/browser-downloads
```

and makes only that directory writable by the Firefox UID/GID.

The Firefox profile is persisted at:

```
/opt/firefox-browser/config
```

## Tested environment

The original deployment was validated on a CyberController lab host with:

- Docker 29.x
- Docker Compose v5.x
- CyberController storage at `/opt/radware/storage`
- `/opt/radware/storage/uploads/temp` owned by UID/GID `1003:1003`
- a restrictive `DOCKER-USER` iptables chain

The scripts verify important assumptions instead of creating a fake `upload/temp` directory when the expected CyberController path is absent.

## Quick deployment

### 1. Clone

Run as a user with root access:

```bash
git clone https://github.com/egori4/cybercontroller-firefox.git
cd cybercontroller-firefox
```

### 2. Review the defaults

```bash
cat .env.example
cat docker-compose.yml
```

Defaults:

```
PUID=1003
PGID=1003
HOST_PORT=3010
CUSTOM_USER=admin
```

If your CyberController uses different ownership for `uploads/temp`, check it first:

```bash
stat -c '%u:%g %A %n' /opt/radware/storage/uploads/temp
```

Adjust `PUID` and `PGID` if required.

### 3. Install

```bash
sudo ./scripts/install.sh
```

On the first run the installer:

1. validates Docker and Docker Compose;
2. verifies the CyberController storage paths;
3. creates the persistent Firefox configuration directory;
4. creates `maintenance/browser-downloads`;
5. generates a random Firefox web password in `.env`;
6. pulls the Firefox image;
7. starts the container.

The generated password is printed once and remains in the local `.env` file, which is excluded from Git.

### 4. Open the host firewall

On the tested CyberController, Docker publishing alone was not enough because `DOCKER-USER` ended with a reject rule.

Run:

```bash
sudo ./scripts/open-firewall.sh
```

Then browse to:

```
https://<CyberController-IP>:3010
```

Use the username and password stored in `.env`.

## Why a normal port-3010 firewall rule did not work

The following rule looks correct but did **not** match traffic to the Docker-published Firefox port:

```bash
iptables -I DOCKER-USER 2 -p tcp --dport 3010 -j ACCEPT
```

Docker DNAT translates:

```
host :3010 -> firefox-container :3001
```

before the packet reaches the `DOCKER-USER` chain. At that point, the packet destination port is already `3001`.

The included firewall helper instead matches the connection's original destination port through conntrack:

```bash
iptables -I DOCKER-USER 2 \
  -p tcp \
  -m conntrack --ctorigdstport 3010 \
  -j ACCEPT
```

This avoids hardcoding the current Firefox container IP.

For troubleshooting, the equivalent container-specific rule is:

```bash
FIREFOX_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' firefox)"

iptables -I DOCKER-USER 2 \
  -d "${FIREFOX_IP}/32" \
  -p tcp --dport 3001 \
  -j ACCEPT
```

That form works, but the container IP can change after recreation.

## Firewall persistence

The included script modifies the active iptables rules only.

CyberController may rebuild its firewall rules during reboot, upgrade, service restart, or configuration changes. Do not blindly save the entire current iptables ruleset on a managed appliance.

If port `3010` stops working after a reboot or firewall reload, re-run:

```bash
sudo ./scripts/open-firewall.sh
```

To remove the rule:

```bash
sudo ./scripts/close-firewall.sh
```

## Operations

Status:

```bash
docker ps --filter name=firefox
docker compose ps
```

Logs:

```bash
docker logs --tail 100 firefox
```

Restart:

```bash
docker compose restart
```

Stop:

```bash
docker compose stop
```

Start:

```bash
docker compose start
```

Remove the container while keeping the persistent Firefox profile:

```bash
docker compose down
```

Update the image:

```bash
docker compose pull
docker compose up -d
```

## Verify storage access

Check the mounts:

```bash
docker inspect firefox --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} (rw={{.RW}}){{println}}{{end}}'
```

Test the upload directory as the configured Firefox UID:

```bash
docker exec -u 1003:1003 firefox \
  sh -c 'touch /config/Downloads/upload-temp/.firefox-test && rm /config/Downloads/upload-temp/.firefox-test'
```

Test the maintenance download directory:

```bash
docker exec -u 1003:1003 firefox \
  sh -c 'touch /config/Downloads/maintenance/.firefox-test && rm /config/Downloads/maintenance/.firefox-test'
```

## Troubleshooting

### Firefox works locally but not remotely

Verify the service first:

```bash
ss -lntp | grep ':3010 '
curl -k -I https://127.0.0.1:3010/
```

With authentication enabled, a local HTTP response of `401 Unauthorized` is expected and confirms the web service is reachable.

Inspect Docker NAT:

```bash
iptables -t nat -L DOCKER -n -v --line-numbers | grep 3010
```

Inspect the CyberController Docker firewall:

```bash
iptables -L DOCKER-USER -n -v --line-numbers
```

If the Docker DNAT counter increases while a raw `--dport 3010` rule remains at zero and a later reject counter increases, the traffic is reaching the host but being rejected after DNAT. Use `scripts/open-firewall.sh`.

### Port 3010 is already in use

Check:

```bash
ss -lntp | grep ':3010 '
```

Change `HOST_PORT` in `.env`, then recreate the container and open that original destination port in the firewall.

### Downloads fail with permission denied

Check the host ownership:

```bash
stat -c '%u:%g %A %n' \
  /opt/radware/storage/uploads/temp \
  /opt/radware/storage/maintenance/browser-downloads
```

The container's `PUID` and `PGID` must be able to write there.

## Security

- Do not expose this browser directly to the public Internet.
- Always use a strong `PASSWORD`.
- Never commit `.env`.
- Restrict network access to trusted management networks where possible.
- Treat the Firefox profile as sensitive; it can contain cookies, sessions, history, and downloaded files.
- The web UI certificate is self-signed by default.
- Review CyberController security and support requirements before deploying on production systems.

## Removal

Remove the container:

```bash
docker compose down
```

Remove the firewall exception:

```bash
sudo ./scripts/close-firewall.sh
```

If the Firefox profile is no longer needed:

```bash
rm -rf /opt/firefox-browser/config
```

Do not remove CyberController storage directories as part of browser cleanup.
