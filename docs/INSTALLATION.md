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
- Ruby matching the PUN's `passenger_ruby` — usually the system Ruby (3.3.x on
  RHEL 9), though some sites pin an rbenv Ruby (e.g. 3.1.2) via `passenger_ruby`.
  `install.sh` detects whichever it is and builds a same-ABI rbenv Ruby to bundle
  against; Rails 6.1 runs on both.
- Node.js 16+ and Yarn 1.x, to build CSS/JS assets
- Slurm client commands on the PUN host and in its `PATH`: `sinfo`, `squeue`,
  `sacct`, `scontrol`, `scancel`, `sshare`

### Known-good versions

The list above gives floors. Two full stacks are verified end-to-end — gems and
packages install clean, assets compile, and the app boots and serves. They
differ only in the PUN's Ruby; `install.sh` detects which and bundles to match:

| Component | Verified (A) | Verified (B) |
| --- | --- | --- |
| Open OnDemand | 4.2.2 | 4.2.2 |
| OS | Rocky Linux 9.8 | Rocky Linux 9.8 |
| Ruby (PUN, built via rbenv) | 3.1.2 | 3.3.10 |
| Bundler | 2.3.6 | 2.5.16 |
| Rails | 6.1.7.6 | 6.1.7.6 |
| Node.js | 18.20.8 | 18.20.8 |
| Yarn | 1.22.22 | 1.22.22 |
| Slurm | 26.05.1 | 26.05.1 |

(A) is a site that pins Ruby 3.1.2 via `passenger_ruby`; (B) leaves it unset, so
Passenger uses the system Ruby (3.3.x on RHEL 9, built as rbenv 3.3.10). On (B)
`install.sh` also pulls a precompiled `nokogiri` (1.19.4 `x86_64-linux-gnu`) so
no gem links a host library. Rails 6.1 runs on both.

Note that the app is forked from the OOD **3.x** dashboard but runs on a **4.x**
portal, because a sandbox app carries its own Rails stack and is not coupled to
the portal's. Do not infer the portal version from the `ood_appkit` /
`ood_core` gems in `Gemfile.lock` — those are client libraries at the versions
the fork pins, not the OOD release.

The app must be bundled for the Ruby the PUN boots it with — its
`passenger_ruby`. At most sites that is unset and resolves to the system Ruby
(3.3.x on RHEL 9); some sites instead pin an rbenv Ruby such as 3.1.2.
`install.sh` detects that Ruby, builds a same-ABI rbenv Ruby (rbenv ships the
build headers the system Ruby usually lacks), vendors the
gems into `vendor/bundle`, and uses **precompiled** native gems so nothing links
a host-specific library. Editing your shell rc does **not** help: the PUN starts
with a scrubbed environment and never sources it, so it always uses
`passenger_ruby`. See
[Troubleshooting](TROUBLESHOOTING.md#bundlergemnotfound-when-the-page-loads-but-the-cli-is-fine).

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

**Run `install.sh` on the OOD web node.** It detects the PUN's Ruby there; on a
login or compute node it can't, and will stop and ask you to run on the host or
pass `PUN_RUBY_ABI` (see below). It then installs a same-ABI rbenv Ruby, vendors
the gems into `vendor/bundle` with precompiled native gems, installs Node
packages, and compiles assets. If you manage Ruby and Node yourself, the
equivalent is:

```bash
bundle config set --local path vendor/bundle
bundle lock --add-platform "$(ruby -e 'print Gem::Platform.local')"
bundle lock --remove-platform ruby     # force self-contained precompiled gems
bundle install
yarn install
bin/recompile_js       # esbuild alone is not enough; this also runs the
                       # Sprockets step the browser actually loads
```

`install.sh` writes `.bundle/config` (`BUNDLE_PATH`) and `.ruby-version`
(gitignored), and may update `Gemfile.lock` — see
[What install.sh changes](#what-installsh-changes).

To install from a fork, set `REPO_SLUG` (and `REPO_HOST` for GitHub Enterprise)
before running `install.sh`:

```bash
REPO_SLUG=myorg/OOD-Dashboard ./install.sh
```

If detection can't run (not on the OOD host) or guesses wrong, override it:

| Variable | Purpose |
| --- | --- |
| `PUN_RUBY` | Path to the interpreter Passenger uses (skips detection) |
| `PUN_RUBY_ABI` | Its `MAJOR.MINOR` (e.g. `3.3`) when the path isn't known |
| `RBENV_VERSION` | Exact rbenv Ruby to build with |
| `BUNDLER_VERSION` | Bundler to use (default: the lockfile's `BUNDLED WITH`) |
| `TARGET_PLATFORM` | Gem platform for precompiled natives (default: this host's) |
| `SKIP_OOD_HOST_CHECK` | Set to `1` to bypass the OOD-host guard |

### What install.sh changes

On a machine the committed `Gemfile.lock` already covers, the build is a no-op on
the lock. It only rewrites version-pinned files when the target needs something
the lock doesn't yet have:

- **`Gemfile.lock`** — adds this host's platform to `PLATFORMS` and drops the
  generic `ruby` platform; if a native gem was still building from source and
  linking a host library, the self-heal step runs `bundle update <gem>` and that
  gem's **pinned version can move** (e.g. `nokogiri 1.15.5 → 1.19.4`). Bundler
  version is taken from `BUNDLED WITH`, so that line does not churn.
- **`.bundle/config`** — sets `BUNDLE_PATH: vendor/bundle` and `BUNDLE_WITHOUT: doc`.
- **`.ruby-version`** — pinned to the rbenv build Ruby (gitignored; not a tracked change).

`Gemfile`, `package.json`, and `yarn.lock` are not touched by the Ruby steps.
Commit a `Gemfile.lock` that already lists every platform you deploy to (and its
precompiled native gems) to keep `install.sh` from modifying it on those hosts.

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
