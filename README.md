# HPC Dashboard

## Overview

HPC Dashboard is a drop-in replacement for the Open OnDemand dashboard — the
Passenger app served at the root of an OOD portal. It keeps everything the stock
dashboard does (app launcher, interactive session management, Files, Projects,
Active Jobs) and adds cluster-aware monitoring on top: allocation and
service-unit balances, storage quotas, live Slurm partition and node status, a
searchable job history with per-job CPU/GPU efficiency metrics, and a site
announcements feed.

It is intended for **HPC system administrators** deploying a portal, not
installed by end users. Installing it replaces the dashboard your users see, so
read [Known Limitations](#known-limitations) before deploying to production.
Installation does not require root if you deploy as a sandbox app; replacing the
system dashboard does.

- Upstream project: [Open OnDemand](https://openondemand.org/)
- Forked from: [OSC/ondemand](https://github.com/OSC/ondemand) dashboard (`apps/dashboard`)

## Try it without a cluster

Before deploying anything, you can click through the whole dashboard with an
invented cluster behind it:

```bash
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git
cd OOD-Dashboard && bundle install && yarn install
OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000
# open http://localhost:3000
```

No Slurm, no Open OnDemand, no root. Stub scheduler tools serve a consistent
fake cluster — 7 partitions, 82 nodes, 250 jobs, 4 allocations, announcements —
so every page and widget is populated. A banner marks the data as invented.

Or run it as a container. On HPC, Apptainer is the path of least resistance and
needs no root:

```bash
apptainer build --ignore-fakeroot-command dashboard-demo.sif demo/apptainer.def
apptainer run --cleanenv dashboard-demo.sif
```

`--cleanenv` matters: without it the host's `LD_PRELOAD` (XALT) leaks in and the
container will not start. A `demo/Dockerfile` mirrors it for Docker sites — see
[demo/README.md](demo/README.md). Demo mode is opt-in and inert when off.

## Screenshots

Here is screenshot for the dashboard:

![Launching the dashboard from the Develop menu](docs/dashboard-demo.png)

## Features

Everything below is in addition to the stock OOD dashboard's functionality.

- **Balance and account widgets** — per-allocation service-unit balances and
  usage, with CSV/XLSX export. Reads Slurm accounting directly via `sacctmgr`
  and `scontrol show assoc`, **not** OOD's balance JSON. Which TRES an
  allocation is denominated in is configurable.
- **Storage widget** — quota and file-count usage per filesystem, with warnings
  as users approach limits and deep links into the Files app. Driven by a
  site-local quota command you name, **not** OOD's quota JSON.
- **System Status widget** — live Slurm partition state: node and core
  allocation, plus GPU allocation derived from `AllocTRES`/`CfgTRES`.
- **Cluster Status page** — every compute node with its state, load, and
  reservations, and a per-node detail page listing the jobs running on it.
- **My Jobs** — searchable, column-filterable job history over an arbitrary date
  range, with charts for job state and GPU-hour distribution, and CSV/XLSX
  export.
- **Job detail pages** — full `scontrol`/`sacct` detail for a single job, linked
  from interactive sessions and My Jobs, with a Cancel action.
- **Per-job efficiency metrics** — CPU utilization, GPU utilization, and memory
  efficiency, via [jobstats](https://github.com/PrincetonUniversity/jobstats)
  (optional; see [Configuration](#3-configure-for-your-site)).
- **GPU-hour accounting** — used and reserved GPU hours per job, with
  configurable charged partitions, discounted QoS, and policy start date.
- **Announcements widget** — outage, maintenance, and announcement articles from
  a site news API, colour-coded by type, with active outages sorted first.
- **Performance Metrics page** — aggregate job efficiency trends for the user.
- **Dashboard Guide** — an in-portal help page explaining each widget.
- **Support ticket integration** — email or Request Tracker (RT) backends,
  using OOD's standard `support_ticket` configuration.

## Requirements

### OOD host software

This app runs on the OOD web node, inside the per-user NGINX (PUN):

- Open OnDemand 3.0+
- Ruby 3.1 (the app is pinned to Rails 6.1; see `Gemfile`)
- Node.js 16+ and Yarn 1.x, to build CSS/JS assets
- Slurm client commands on the PUN host and in its `PATH`: `sinfo`, `squeue`,
  `sacct`, `scontrol`, `scancel`, `sshare`

### Scheduler

- **Slurm only.** Unlike the stock dashboard, the monitoring features here shell
  out to Slurm commands and parse their output. PBS, LSF, and Kubernetes
  clusters will still work for app launching and interactive sessions, but the
  balance, partition, node, and job-history pages will be empty.

### Optional

- [jobstats](https://github.com/PrincetonUniversity/jobstats) and a Prometheus
  instance, for per-job CPU/GPU utilization and memory efficiency. Requires a
  Python interpreter with jobstats' dependencies (notably `requests`) reachable
  from the PUN host.
- A JSON news/announcements API, for the Announcements widget.
- A quota-reporting command on the PUN host, for the Storage widget — named via
  `OOD_QUOTA_COMMAND`, see [Storage and allocations](#storage-and-allocations)
  for the output format it must produce.
- Quota and balance JSON in OOD's standard formats, for the stock warning
  banners (separate from the widgets above).

## Quick Start

An evaluation path for a Slurm site, start to finish in about an hour. It
touches nothing your users see. The full detail for each step is in
[App Installation](#app-installation) below.

### 0. Look at it first, without a cluster

`OOD_DEMO_MODE=true bundle exec rails server` gives you every page populated
with invented data — see [Try it without a cluster](#try-it-without-a-cluster).
Worth doing before you spend time on the steps below.

### 1. Check prerequisites on the OOD web node

Run these **as the web user**, since what matters is whether they work inside
the PUN rather than on a login node:

```bash
sinfo -h -o '%R|%a|%F|%C'          # System Status widget
scontrol show node --oneliner      # Cluster Status page
sacct -X -u "$USER" -S now-1week -P -n   # My Jobs, Performance Metrics
sacctmgr show user "$USER" withassoc format=account -P -n   # Accounts widget
```

**Slurm accounting (slurmdbd) is required.** Without a working `sacct`, the job
history, job detail, and performance pages are all empty.

### 2. Enable sandbox mode for one administrator

```bash
# As root on the OOD web node
user="alice"
mkdir -p "/var/www/ood/apps/dev/$user"
ln -s "/home/$user/ondemand/dev" "/var/www/ood/apps/dev/$user/gateway"
```

This is the only step needing root, and it changes nothing for regular users. If
the host is configuration-managed, make the change there or it will be reverted
on the next run. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

### 3. Clone and build

```bash
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
./install.sh
```

### 4. Set the two values worth setting

```bash
cp .env.local.example .env.local
# then edit .env.local down to just:
#   OOD_SITE_NAME="Your Cluster"
#   OOD_DASHBOARD_DOCS_URL="https://docs.example.edu/"
```

Everything else is optional. Any feature whose configuration is missing hides
itself or reports `N/A` rather than erroring, so this is genuinely enough to
boot.

### 5. Launch and check the baseline

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

### 6. Point the two site-specific data sources at your cluster

Both are configuration now, but neither has a portable default:

- **`OOD_QUOTA_COMMAND`** — the Storage widget needs a command that reports
  quotas for a username. Unset, the widget is simply absent.
- **`OOD_GPU_ACCOUNT_PATTERN`** — if you denominate some allocations in GPU time
  rather than CPU time, this is how the Accounts and Balance widgets tell them
  apart. Unset, every account is read as CPU-denominated. Set it wrong and GPU
  allocations are reported as CPU ones silently, with plausible-looking numbers,
  so check it against your account naming.

Both are documented under
[Storage and allocations](#storage-and-allocations).

### 7. Layer on the optional integrations

One at a time, verifying each: announcements (`OOD_NEWS_FEED_URL`), GPU-hour
accounting (`OOD_GPU_HOURS_PARTITIONS`), per-job efficiency metrics
(`OOD_JOBSTATS_PYTHON`/`OOD_JOBSTATS_SCRIPT`), support tickets. See
[Configure for your site](#3-configure-for-your-site).

### 8. Only then consider replacing the system dashboard

Back up `/var/www/ood/apps/sys/dashboard` first, and go in knowing you are
adopting a fork: upstream OOD dashboard updates must be merged in, not applied
by upgrading OOD. See [Known Limitations](#known-limitations).

## App Installation

### 1. Choose a deployment mode

**Sandbox (recommended first)** — deploy under `~/ondemand/dev` and reach it via
*Develop → My Sandbox Apps*. Nothing your users see changes, and no root is
needed. Use this to evaluate the app and work out your configuration.

**System dashboard** — replace `/var/www/ood/apps/sys/dashboard`. This changes
the portal for every user; take a backup of the existing directory first.

### 2. Clone the repository

```bash
# Sandbox deployment
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
```

Then build it. The provided script installs Ruby 3.1.2 via rbenv, installs gems
and Node packages, and compiles assets:

```bash
./install.sh
```

If you manage Ruby and Node yourself, the equivalent is:

```bash
bundle install
yarn install
bin/recompile_js       # esbuild alone is not enough; this also runs the
                       # Sprockets step the browser actually loads
```

To install from a fork, set `REPO_SLUG` (and `REPO_HOST` for GitHub
Enterprise) before running `install.sh`:

```bash
REPO_SLUG=myorg/OOD-Dashboard ./install.sh
```

### 3. Configure for your site

**All site-specific values are configuration — you should not need to edit any
view or controller.** `.env.local.example` is the annotated master list; it uses
Purdue's Gautschi cluster as a worked example, so replace those values with your
own.

Each key can be set three ways, in precedence order:

1. `OOD_<KEY>` in the environment (including `/etc/ood/config/apps/dashboard/env`)
2. the key without the `OOD_` prefix in `/etc/ood/config/apps/dashboard/*.yml`
3. `.env.local` in the app directory — **development only**

For production, prefer `/etc/ood/config/apps/dashboard/`, so your configuration
lives outside the checkout and survives upgrades.

Every key is optional. A feature whose configuration is missing hides itself or
reports `N/A` rather than erroring, so an unconfigured deployment boots and
behaves like the stock dashboard.

#### Branding

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_SITE_NAME` | Short cluster/service name, used throughout the UI | OOD dashboard title |
| `OOD_SITE_LOGO_URL` | Logo beside the site name in the sidebar | none (text only) |

#### Documentation links

Each topic link falls back to `OOD_DASHBOARD_DOCS_URL`; if that is also unset,
the widget's info icon is not rendered.

| Key | Links from |
|-----|-----------|
| `OOD_DASHBOARD_DOCS_URL` | *User Guide* in the navbar; fallback for all below |
| `OOD_DASHBOARD_SUPPORT_URL` | *Need Help?* button and Dashboard Guide |
| `OOD_DOCS_ACCOUNTS_URL` | Accounts and Balance Usage widgets |
| `OOD_DOCS_PARTITIONS_URL` | System Status widget |
| `OOD_DOCS_STORAGE_URL` | Storage widget |
| `OOD_DOCS_NODES_URL` | Cluster Status page |

#### Announcements

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_NEWS_FEED_URL` | JSON news endpoint; unset disables the widget | none |
| `OOD_NEWS_FEED_RESOURCE_FILTER` | Keep only articles tagged with this resource name | keep all |
| `OOD_NEWS_PAGE_URL` | Human-facing archive, linked as *View All* | none |

The widget expects the response shape produced by Purdue RCAC's news API:
a `data` array whose entries carry `headline`, `uri`, `formattedbody`,
`datetimenews`, `datetimenewsend`, `newstypeid`, and optional `updates` and
`resources`. Article types are mapped in `NEWS_TYPE_IDS` in
`app/controllers/api/news_feed_controller.rb`. **If your news system differs,
that controller is the one file you will need to adapt** — it is the only
place the feed format is assumed.

#### Storage and allocations

Note these keys drive the **stock OOD warning banners**, which are separate from
the Storage and Accounts widgets described above. Those widgets shell out to
`myquota` and `sacctmgr` instead — see [Known Limitations](#known-limitations).

**Storage widget.** Driven by a command you supply, since no portable way to
query quotas exists. Unset, the widget is absent.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_QUOTA_COMMAND` | Command reporting quotas, given the username as its only argument | none (widget hidden) |
| `OOD_QUOTA_COMMAND_SKIP_LINES` | Header rows to skip before the first data row | `3` |
| `OOD_SCRATCH_DIR_TEMPLATE` | Scratch path for `scratch`-type rows; `$USER` is expanded | `/<type>/<location>` |

Its output must be whitespace-separated columns, after the skipped header rows:

```
type     location            disk_used disk_limit disk_pct files   file_limit file_pct
home     /home/alice         38.2GB    100GB      38%      412031  1000000    41%
scratch  /scratch/alice      1.4TB     5TB        28%      883122  2000000    44%
```

`demo/bin/myquota` is a working example.

**Accounts and Balance widgets.** These read Slurm accounting directly. Slurm
records a balance under a TRES name that depends on what the allocation is
denominated in, and sites tell those apart by account naming.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_GPU_ACCOUNT_PATTERN` | Regex matching GPU-denominated account names | none (all accounts read as CPU) |
| `OOD_GPU_ACCOUNT_TRES` | TRES holding the balance for matching accounts | `gres/gpu` |
| `OOD_CPU_ACCOUNT_TRES` | TRES holding the balance for all other accounts | `cpu` |

Prefer `"-gpu$"` over `"-gpu\z"`: unquoted, `\z` is parsed as a literal `z` and
matches nothing. An invalid regex is logged and treated as no pattern.

**Stock OOD warning banners.** Separate from the widgets above.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_QUOTA_PATH` | Colon-separated quota JSON files/URLs | none |
| `OOD_QUOTA_THRESHOLD` | Warn above this usage fraction | `0.95` |
| `OOD_BALANCE_PATH` | Colon-separated balance JSON files/URLs | none |
| `OOD_BALANCE_THRESHOLD` | Warn below this balance | `0` |

#### Partitions

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_EXCLUDED_PARTITIONS` | Comma-separated partitions to hide from System Status | show all |

#### GPU-hour accounting

GPU-hour charging is site policy. Leave `OOD_GPU_HOURS_PARTITIONS` unset and all
jobs report GPU hours as `N/A` — correct for sites that do not charge separately
for GPU time.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_GPU_HOURS_PARTITIONS` | Comma-separated partitions charged for GPU hours | none (feature off) |
| `OOD_GPU_HOURS_MIN_JOB_ID` | Jobs at or below this id predate the policy and report `N/A` | `0` |
| `OOD_GPU_HOURS_DISCOUNTED_QOS` | A QoS charged at a reduced rate | none |
| `OOD_GPU_HOURS_DISCOUNTED_CHARGE_FACTOR` | Multiplier for that QoS | `0.25` |

#### Per-job efficiency metrics

Both keys must be set for the utilization and memory-efficiency columns to
appear; unset, they are omitted.

| Key | Description |
|-----|-------------|
| `OOD_JOBSTATS_PYTHON` | Interpreter that has jobstats' dependencies |
| `OOD_JOBSTATS_SCRIPT` | Path to the `jobstats` script |

jobstats ships a `#!/usr/bin/env python3` shebang, which on a PUN host often
resolves to an interpreter without its `requests` dependency. Rather than
executing the script directly, the dashboard invokes it as an argument to the
interpreter you name here, so its local imports still resolve.

#### Support tickets

Uses OOD's standard `support_ticket` configuration in
`/etc/ood/config/apps/dashboard/*.yml` — email and Request Tracker (RT) backends
are supported. See the
[OOD support ticket docs](https://osc.github.io/ood-documentation/latest/customizations.html#support-ticket-form).

### 4. Verify

For a sandbox deployment:

1. In the portal, open **Develop → My Sandbox Apps (Development)**.
2. Find **HPC Dashboard**, click **Launch HPC Dashboard**.
3. If you see *App has not been initialized or does not exist*, click
   **Initialize App**.

For a system dashboard deployment, restart the PUN (*Develop → Restart Web
Server*, or `/nginx/stop`) and reload the portal root.

Then confirm:

- The sidebar brand shows your `OOD_SITE_NAME`.
- **System Status** lists your partitions, minus any you excluded.
- **Cluster Status** lists nodes, and clicking one shows its jobs.
- **My Jobs** returns your job history for a chosen date range.
- Widgets you did not configure (Storage, Balance, Announcements) are absent
  rather than broken.

## Configuration Reference

`.env.local.example` is the authoritative annotated list of every key, grouped
by feature. In code, the site configuration layer is:

- `config/configuration_singleton.rb` — `site_string_configs` defines the keys
  and their defaults, and reads them from environment or config file.
- `app/helpers/application_helper.rb` — view-facing helpers, including the
  documentation-link fallbacks.
- `app/views/shared/_docs_info_link.html.erb` — the per-widget info icon, which
  renders nothing when no URL is configured.

## Troubleshooting

### Widgets show "Failed to load"

The dashboard's monitoring endpoints shell out to Slurm. Confirm the commands
work as the web user on the OOD host:

```bash
sinfo -h -o '%R|%a|%F|%C'
scontrol show node --oneliner | head -1
sacct -X -u "$USER" -S now-1week -P -n | head
```

An empty `PATH` inside the PUN is the usual cause. Check
`~/ondemand/data/sys/dashboard/` and the Rails log under `log/` for the
underlying error.

### Efficiency metrics columns are missing

Expected when `OOD_JOBSTATS_PYTHON`/`OOD_JOBSTATS_SCRIPT` are unset. If they
are set, run the exact command the dashboard runs:

```bash
"$OOD_JOBSTATS_PYTHON" "$OOD_JOBSTATS_SCRIPT" -j <jobid>
```

A `ModuleNotFoundError: requests` means the interpreter you named lacks
jobstats' dependencies. Failures are logged at `info` level and the metrics are
skipped rather than surfaced as errors.

### Announcements widget is empty

Confirm `OOD_NEWS_FEED_URL` returns JSON from the OOD host, and that
`OOD_NEWS_FEED_RESOURCE_FILTER` matches a `resources[].name` in the response —
a filter that matches nothing yields an empty widget. The response is cached for
30 minutes; the cache key includes the URL and filter, so config changes take
effect immediately.

### GPU hours all show "N/A"

Expected unless `OOD_GPU_HOURS_PARTITIONS` names the job's partition and the job
id is above `OOD_GPU_HOURS_MIN_JOB_ID`.

### JS changes do not appear

Run `bin/recompile_js`. Running esbuild alone leaves the Sprockets-served bundle
stale.

## Testing

| Site | OOD Version | Scheduler | Status |
|------|-------------|-----------|--------|
| Purdue RCAC (Gautschi) | 3.1 | Slurm | In production |

**There is no automated test suite.** The upstream dashboard's tests were not
carried over into this fork, so `bin/rails test` runs zero tests. Changes are
verified manually against a sandbox deployment using the checklist in
[Verify](#4-verify) above. Restoring upstream's test suite is an open task and a
welcome contribution.

## Known Limitations

- **Slurm only.** The monitoring features parse Slurm command output. Other
  schedulers lose those pages, though app launching still works.
- **Replaces the dashboard.** This is a fork of the OOD dashboard, not an app
  installed alongside it. Deploying it as the system dashboard means you are
  maintaining a fork: OOD dashboard updates must be merged in rather than
  applied by upgrading OOD.
- **Forked from OOD 3.x / Rails 6.1.** It has not been rebased onto newer
  upstream dashboard releases.
- **The news feed format is site-specific.** Only Purdue RCAC's news API shape
  is implemented; other news systems require adapting one controller.
- **The Storage widget needs a quota command you supply.** There is no portable
  way to ask a cluster for quotas, so `OOD_QUOTA_COMMAND` names a site-local
  wrapper and the widget parses its columns. Without one the widget is absent
  rather than broken, but you get no storage reporting until you write it.
- **The Accounts widget still assumes two TRES names.** `OOD_GPU_ACCOUNT_TRES`
  and `OOD_CPU_ACCOUNT_TRES` cover the balance figures, but the live core counts
  in `api/account_list_controller.rb` still read the `gres/hp_cpu` and `billing`
  TRES directly. Sites that do not define those will see that widget fail.
- **Only tested on RHEL 9 with Slurm.** Other combinations are untested.

## Contributing

Contributions are welcome:

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Open a pull request describing your changes

Please keep site-specific values out of views and controllers — add a key to
`site_string_configs` in `config/configuration_singleton.rb` and document it in
`.env.local.example` instead.

For bugs or feature requests,
[open an issue](https://github.com/PurdueRCAC/OOD-Dashboard/issues).

This app is part of the
[OOD Appverse](https://openondemand.connectci.org/affinity-groups/ood-appverse).

## References

- [Open OnDemand](https://openondemand.org/) — the portal framework
- [OSC/ondemand](https://github.com/OSC/ondemand) — upstream dashboard this is
  forked from
- [jobstats](https://github.com/PrincetonUniversity/jobstats) — per-job
  efficiency metrics
- [Slurm_tools `showpartitions`](https://github.com/OleHolmNielsen/Slurm_tools/blob/master/partitions/showpartitions)
  — the partition status widget's Slurm queries are derived from this
- [OOD app development guide](https://osc.github.io/ood-documentation/latest/how-tos/app-development.html)
- Development and sandbox setup notes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)

The balance and service-unit widgets originate in the Anvil OOD dashboard.

## License

[MIT License](LICENSE) — © Ohio Supercomputer Center (upstream dashboard) and
Purdue University Research Computing.

## Acknowledgments

Built by [Purdue University Research Computing (RCAC)](https://www.rcac.purdue.edu/)
on top of Open OnDemand, which is supported by NSF awards 1534949, 1835725,
2138286, 2303692, and 2411375.
