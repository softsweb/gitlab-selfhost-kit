# gitlab-selfhost-kit

Install your own GitLab Community Edition on a VPS with one command. The script asks one question, the address of your GitLab, and does the rest.

Made for the SoftsWeb video "Self-Host GitLab + GitLab Runner" (link in the video description).

## Before you start

1. A VPS running Ubuntu or Debian, with at least 4 GB of memory (GitLab recommends 8 GB for a comfortable setup).
2. A domain name. Create an **A record** (for example `git`) that points to your server's IP address, so `git.example.com` opens your server. The free certificate is issued for that name.
3. Ports 80, 443 and 2424 free on the server. GitLab's own Git over SSH uses 2424, so your normal SSH login on port 22 is not touched.

## Install

```bash
git clone https://github.com/softsweb/gitlab-selfhost-kit.git
cd gitlab-selfhost-kit
sudo ./install.sh
```

When it asks, type the address of your GitLab, for example `git.example.com`.

You can also skip the question: `sudo ./install.sh git.example.com`.

## What the script does

- checks the address, the memory, the free ports and whether your DNS points to this server;
- installs Docker with Docker's official install script if it is missing;
- writes `/opt/gitlab/docker-compose.yml` for the official `gitlab/gitlab-ce` image, with a free Let's Encrypt certificate;
- opens ports 80, 443 and 2424 if the `ufw` firewall is active;
- starts GitLab and waits until the sign-in page answers (the first start takes a few minutes);
- prints how to read the first `root` password.

Try it without installing anything: `./install.sh --dry-run git.example.com` only writes the compose file into `./out`.

## Good to know

- By default it uses the `latest` GitLab image. For a long-lived server, pin a version: `GITLAB_VERSION=18.5.1-ce.0 sudo -E ./install.sh git.example.com` (check the available tags on Docker Hub, `gitlab/gitlab-ce`).
- The first `root` password is stored in `/etc/gitlab/initial_root_password` inside the container and GitLab deletes it after 24 hours. Read it, sign in and change it straight away.
- Your data lives in `/opt/gitlab/config`, `/opt/gitlab/logs` and `/opt/gitlab/data`. Back them up somewhere other than the same server.
- Status: the script was syntax checked and its dry run and generated compose file were validated. Test it on a fresh server before you rely on it.

## Remove it

```bash
cd /opt/gitlab && sudo docker compose down
# add -v and delete /opt/gitlab only if you want to erase all the data
```

## Affiliate disclosure

Some links in the video description are affiliate links. If you use them SoftsWeb may earn a commission at no extra cost to you. You do not need them to use this script.

## License

MIT
