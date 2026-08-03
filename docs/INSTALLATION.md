# Installation

Full detail for deploying the dashboard on an OOD web node. For a time-boxed
evaluation path, follow the [Quick Start](QUICKSTART.md) instead.

- [Requirements](#requirements)
- [1. Choose a deployment mode](#1-choose-a-deployment-mode)
- [2. Clone and build](#2-clone-and-build)
- [3. Configure for your site](#3-configure-for-your-site)
- [4. Verify](#4-verify)

## Requirements

### OOD host software

This app runs on the OOD web node, inside the per-user NGINX (PUN):

- Open OnDemand 3.0+
- Ruby 3.1 (the app is pinned to Rails 6.1; see `Gemfile`)
- Node.js 16+ and Yarn 1.x, to build CSS/JS assets
- Slurm client commands on the PUN host and in its `PATH`: `sinfo`, `squeue`,
  `sacct`, `scontrol`, `scancel`, `sshare`

### Scheduler

**Slurm only.** Unlike the stock dashboard, the monitoring features here shell
out to Slurm commands and parse their output. PBS, LSF, and Kubernetes clusters
will still work for app launching and interactive sessions, but the balance,
partition, node, and job-history pages will be empty.

**Slurm accounting (slurmdbd) is required.** Without a working `sacct`, the job
history, job detail, and performance pages are all empty.

### Optional

- [jobstats](https://github.com/PrincetonUniversity/jobstats) and a Prometheus
  instance, for per-job CPU/GPU utilization and memory efficiency. Requires a
  Python interpreter with jobstats' dependencies (notably `requests`) reachable
  from the PUN host.
- A JSON news/announcements API, for the Announcements widget.
- A quota-reporting command on the PUN host, for the Storage widget — named via
  `OOD_QUOTA_COMMAND`; see
  [Storage widget](CONFIGURATION.md#storage-widget) for the output format it
  must produce.
- Quota and balance JSON in OOD's standard formats, for the stock warning
  banners (separate from the widgets above).

## 1. Choose a deployment mode

**Sandbox (recommended first)** — deploy under `~/ondemand/dev` and reach it via
*Develop → My Sandbox Apps*. Nothing your users see changes, and no root is
needed. Use this to evaluate the app and work out your configuration.

**System dashboard** — replace `/var/www/ood/apps/sys/dashboard`. This changes
the portal for every user; take a backup of the existing directory first, and
read [Known Limitations](LIMITATIONS.md) before you do.

Sandbox mode needs one root step per administrator, which changes nothing for
regular users:

```bash
# As root on the OOD web node
user="alice"
mkdir -p "/var/www/ood/apps/dev/$user"
ln -s "/home/$user/ondemand/dev" "/var/www/ood/apps/dev/$user/gateway"
```

If the host is configuration-managed, make the change there or it will be
reverted on the next run. See [DEVELOPMENT.md](DEVELOPMENT.md).

## 2. Clone and build

```bash
# Sandbox deployment
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
./install.sh
```

`install.sh` installs Ruby 3.1.2 via rbenv, installs gems and Node packages, and
compiles assets. If you manage Ruby and Node yourself, the equivalent is:

```bash
bundle install
yarn install
bin/recompile_js       # esbuild alone is not enough; this also runs the
                       # Sprockets step the browser actually loads
```

To install from a fork, set `REPO_SLUG` (and `REPO_HOST` for GitHub Enterprise)
before running `install.sh`:

```bash
REPO_SLUG=myorg/OOD-Dashboard ./install.sh
```

## 3. Configure for your site

See the [Configuration reference](CONFIGURATION.md) for every key. The short
version: copy `.env.local.example` to `.env.local` for development, or put keys
under `/etc/ood/config/apps/dashboard/` for production.

Two values are worth setting immediately:

```bash
OOD_SITE_NAME="Your Cluster"
OOD_DASHBOARD_DOCS_URL="https://docs.example.edu/"
```

Two more have no portable default and gate real features:

- **`OOD_QUOTA_COMMAND`** — the Storage widget needs a command that reports
  quotas for a username. Unset, the widget is simply absent.
- **`OOD_GPU_ACCOUNT_PATTERN`** — if you denominate some allocations in GPU time
  rather than CPU time, this is how the Accounts and Balance widgets tell them
  apart. Unset, every account is read as CPU-denominated.

## 4. Verify

For a sandbox deployment:

1. In the portal, open **Develop → My Sandbox Apps (Development)**.
2. Find **HPC Dashboard**, click **Launch HPC Dashboard**.
3. If you see *App has not been initialized or does not exist*, click
   **Initialize App**.

For a system dashboard deployment, restart the PUN (*Develop → Restart Web
Server*, or `/nginx/stop`) and reload the portal root.

Then confirm:

- [ ] The sidebar brand shows your `OOD_SITE_NAME`.
- [ ] **System Status** lists your partitions, minus any you excluded.
- [ ] **Cluster Status** lists nodes, and clicking one shows its jobs.
- [ ] **My Jobs** returns your job history for a chosen date range.
- [ ] Widgets you did not configure (Storage, Balance, Announcements) are absent
      rather than broken.

`demo/smoke.sh <url>` requests every page and JSON endpoint and exits non-zero
on failure. It works against a real deployment too — there an empty Storage or
Accounts result means the site configuration is not wired up.

If something does not work, see [Troubleshooting](TROUBLESHOOTING.md).
