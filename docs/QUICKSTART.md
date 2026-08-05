# Quick Start

An evaluation path for a Slurm site, start to finish in about an hour. It
touches nothing your users see. Full detail for each step is in
[Installation](INSTALLATION.md).

## 0. Look at it first, without a cluster

```bash
OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000
```

Every page populated with invented data — no Slurm, no OOD, no root. See
[demo/README.md](../demo/README.md). Worth doing before you spend time on the
steps below.

## 1. Check prerequisites on the OOD web node

Run these **as the web user**, since what matters is whether they work inside
the PUN rather than on a login node:

```bash
sinfo -h -o '%R|%a|%F|%C'                                   # System Status widget
scontrol show node --oneliner                               # Cluster Status page
sacct -X -u "$USER" -S now-1week -P -n                      # My Jobs, Performance Metrics
sacctmgr show user "$USER" withassoc format=account -P -n   # Accounts widget
```

**Slurm accounting (slurmdbd) is required.** Without a working `sacct`, the job
history, job detail, and performance pages are all empty.

## 2. Enable sandbox mode for one administrator

```bash
# As root on the OOD web node
user="alice"
mkdir -p "/var/www/ood/apps/dev/$user"
ln -s "/home/$user/ondemand/dev" "/var/www/ood/apps/dev/$user/gateway"
```

This is the only step needing root, and it changes nothing for regular users. If
the host is configuration-managed, make the change there or it will be reverted
on the next run. See [DEVELOPMENT.md](DEVELOPMENT.md).

## 3. Clone and build

```bash
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
./install.sh
```

Run this on the OOD web node — `install.sh` detects the PUN's Ruby there and
bundles for it. On another node it will stop and ask you to run on the host or
pass `PUN_RUBY_ABI` (see [Installation](INSTALLATION.md#2-clone-and-build)).

## 4. Set the two values worth setting

```bash
cp .env.local.example .env.local
# then edit .env.local down to just:
#   OOD_SITE_NAME="Your Cluster"
#   OOD_DASHBOARD_DOCS_URL="https://docs.example.edu/"
```

Everything else is optional. Any feature whose configuration is missing hides
itself or reports `N/A` rather than erroring, so this is genuinely enough to
boot.

## 5. Launch and check the baseline

*Develop → My Sandbox Apps (Development) → Launch HPC Dashboard*. If you see
*App has not been initialized or does not exist*, click **Initialize App**.

On any Slurm site with accounting, these work with no further configuration:

| Works out of the box | Needs |
|---|---|
| System Status widget | `sinfo`, `scontrol` |
| Cluster Status page and node detail | `scontrol` |
| My Jobs, job detail, Cancel Job | `sacct`, `scontrol`, `scancel` |
| Performance Metrics page | `sacct` |
| Accounts and Balance widgets | `sacctmgr`, `scontrol show assoc` |
| App launcher, sessions, Files, Projects | stock OOD behaviour |

## 6. Point the two site-specific data sources at your cluster

Both are configuration now, but neither has a portable default:

- **`OOD_QUOTA_COMMAND`** — the Storage widget needs a command that reports
  quotas for a username. Unset, the widget is simply absent.
- **`OOD_GPU_ACCOUNT_PATTERN`** — if you denominate some allocations in GPU time
  rather than CPU time, this is how the Accounts and Balance widgets tell them
  apart. Unset, every account is read as CPU-denominated. Set it wrong and GPU
  allocations are reported as CPU ones silently, with plausible-looking numbers,
  so check it against your account naming.

Both are documented in the
[Configuration reference](CONFIGURATION.md#storage-widget).

## 7. Layer on the optional integrations

One at a time, verifying each:

| Feature | Keys |
|---|---|
| Announcements | `OOD_NEWS_FEED_URL` |
| GPU-hour accounting | `OOD_GPU_HOURS_PARTITIONS` |
| Per-job efficiency metrics | `OOD_JOBSTATS_PYTHON`, `OOD_JOBSTATS_SCRIPT` |
| Support tickets | OOD's standard `support_ticket` config |

See the [Configuration reference](CONFIGURATION.md).

## 8. Only then consider replacing the system dashboard

Back up `/var/www/ood/apps/sys/dashboard` first, and go in knowing you are
adopting a fork: upstream OOD dashboard updates must be merged in, not applied
by upgrading OOD. See [Known Limitations](LIMITATIONS.md).
