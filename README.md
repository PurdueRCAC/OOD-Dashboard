# HPC Dashboard

A drop-in replacement for the Open OnDemand dashboard that adds cluster-aware
monitoring: allocation balances, storage quotas, live Slurm partition and node
status, searchable job history with per-job efficiency metrics, and site
announcements — on top of everything the stock dashboard already does.

[![Open OnDemand 3.0+](https://img.shields.io/badge/Open%20OnDemand-3.0%2B-informational)](https://openondemand.org/)
[![Scheduler: Slurm](https://img.shields.io/badge/scheduler-Slurm-informational)](https://slurm.schedmd.com/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![The HPC Dashboard home page](docs/dashboard-demo.png)

> [!IMPORTANT]
> This is for **HPC system administrators** deploying a portal, not for end
> users. Installing it replaces the dashboard your users see — read
> [Known Limitations](docs/LIMITATIONS.md) first. Deploying as a sandbox app
> needs no root; replacing the system dashboard does.

## Try it without a cluster

No Slurm, no Open OnDemand, no root — stub scheduler tools serve a consistent
fake cluster (7 partitions, 82 nodes, 250 jobs, 4 allocations) so every page and
widget is populated. A banner marks the data as invented.

```bash
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git
cd OOD-Dashboard && bundle install && yarn install
OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000
# open http://localhost:3000
```

<details>
<summary><b>Prefer a container?</b> Apptainer needs no root and is the path of least resistance on HPC</summary>

```bash
apptainer build --ignore-fakeroot-command dashboard-demo.sif demo/apptainer.def
apptainer run --cleanenv dashboard-demo.sif
```

`--cleanenv` matters: without it the host's `LD_PRELOAD` (XALT) leaks in and the
container will not start. A `demo/Dockerfile` mirrors it for Docker sites.
Demo mode is opt-in and inert when off — see [demo/README.md](demo/README.md).

</details>

## Features

Everything below is *in addition to* the stock OOD dashboard's app launcher,
interactive sessions, Files, Projects, and Active Jobs.

<details>
<summary><b>Allocations and storage</b> — balances, service units, quotas</summary>

- **Balance and account widgets** — per-allocation service-unit balances and
  usage, with CSV/XLSX export. Reads Slurm accounting directly via `sacctmgr`
  and `scontrol show assoc`, **not** OOD's balance JSON. Which TRES an
  allocation is denominated in is configurable.
- **Storage widget** — quota and file-count usage per filesystem, with warnings
  as users approach limits and deep links into the Files app. Driven by a
  site-local quota command you name, **not** OOD's quota JSON.

</details>

<details>
<summary><b>Cluster monitoring</b> — partitions, nodes, reservations</summary>

- **System Status widget** — live Slurm partition state: node and core
  allocation, plus GPU allocation derived from `AllocTRES`/`CfgTRES`.
- **Cluster Status page** — every compute node with its state, load, and
  reservations, and a per-node detail page listing the jobs running on it.

</details>

<details>
<summary><b>Jobs and efficiency</b> — history, detail pages, utilization metrics</summary>

- **My Jobs** — searchable, column-filterable job history over an arbitrary date
  range, with charts for job state and GPU-hour distribution, and CSV/XLSX
  export.
- **Job detail pages** — full `scontrol`/`sacct` detail for a single job, linked
  from interactive sessions and My Jobs, with a Cancel action.
- **Per-job efficiency metrics** — CPU utilization, GPU utilization, and memory
  efficiency, via [jobstats](https://github.com/PrincetonUniversity/jobstats)
  (optional).
- **GPU-hour accounting** — used and reserved GPU hours per job, with
  configurable charged partitions, discounted QoS, and policy start date.
- **Performance Metrics page** — aggregate job efficiency trends for the user.

</details>

<details>
<summary><b>Communication</b> — announcements, help, support tickets</summary>

- **Announcements widget** — outage, maintenance, and announcement articles from
  a site news API, colour-coded by type, with active outages sorted first.
- **Dashboard Guide** — an in-portal help page explaining each widget.
- **Support ticket integration** — email or Request Tracker (RT) backends, using
  OOD's standard `support_ticket` configuration.

</details>

## Install it

Requires Open OnDemand 3.0+, Ruby 3.1, Node 16+, and Slurm client commands
reachable from the PUN host. Deploy as a sandbox app first — nothing your users
see changes:

```bash
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
./install.sh
```

Then launch it from *Develop → My Sandbox Apps (Development)*.

**Every site-specific value is configuration — you should not need to edit any
view or controller.** Any feature whose configuration is missing hides itself or
reports `N/A` rather than erroring, so this boots and behaves like the stock
dashboard before you configure anything. Two values are worth setting right
away:

```bash
OOD_SITE_NAME="Your Cluster"
OOD_DASHBOARD_DOCS_URL="https://docs.example.edu/"
```

➡️ **[Quick Start](docs/QUICKSTART.md)** — the full evaluation path, about an hour
&nbsp;·&nbsp; **[Installation](docs/INSTALLATION.md)** &nbsp;·&nbsp;
**[Configuration](docs/CONFIGURATION.md)**

## Documentation

| Document | What's in it |
|---|---|
| [Quick Start](docs/QUICKSTART.md) | Evaluation path for a Slurm site, touching nothing your users see |
| [Installation](docs/INSTALLATION.md) | Requirements, deployment modes, build, verification checklist |
| [Configuration](docs/CONFIGURATION.md) | Every `OOD_*` key, grouped by feature, with defaults and formats |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Symptom-first fixes for empty widgets, missing metrics, stale assets |
| [Known Limitations](docs/LIMITATIONS.md) | What this fork does not do, and what needs site-local work |
| [Development](docs/DEVELOPMENT.md) | Working on the dashboard itself |
| [Demo mode](demo/README.md) | Running the whole dashboard with an invented cluster behind it |

## Before you deploy

<details>
<summary><b>Four things worth knowing up front</b></summary>

- **Slurm only.** The monitoring features parse Slurm command output. Other
  schedulers keep app launching but lose those pages.
- **You are adopting a fork.** This replaces the OOD dashboard rather than
  installing alongside it, so upstream updates must be merged in, not applied by
  upgrading OOD.
- **Two features need site-local work.** The news feed assumes Purdue RCAC's API
  shape, and the Storage widget needs a quota command you supply.
- **There is no automated test suite.** Upstream's tests were not carried into
  this fork. Changes are verified manually against a sandbox deployment.

Full detail in [Known Limitations](docs/LIMITATIONS.md).

</details>

## Contributing

Fork, branch, and open a pull request describing your changes. Please keep
site-specific values out of views and controllers — add a key to
`site_string_configs` in `config/configuration_singleton.rb` and document it in
`.env.local.example` instead. See [Development](docs/DEVELOPMENT.md).

For bugs or feature requests,
[open an issue](https://github.com/PurdueRCAC/OOD-Dashboard/issues).

This app is part of the
[OOD Appverse](https://openondemand.connectci.org/affinity-groups/ood-appverse).

<details>
<summary><b>References</b></summary>

- [Open OnDemand](https://openondemand.org/) — the portal framework
- [OSC/ondemand](https://github.com/OSC/ondemand) — upstream dashboard this is
  forked from (`apps/dashboard`)
- [jobstats](https://github.com/PrincetonUniversity/jobstats) — per-job
  efficiency metrics
- [Slurm_tools `showpartitions`](https://github.com/OleHolmNielsen/Slurm_tools/blob/master/partitions/showpartitions)
  — the partition status widget's Slurm queries are derived from this
- [OOD app development guide](https://osc.github.io/ood-documentation/latest/how-tos/app-development.html)

The balance and service-unit widgets originate in the Anvil OOD dashboard.

</details>

## License

[MIT License](LICENSE) — © Ohio Supercomputer Center (upstream dashboard) and
Purdue University Research Computing.

Built by [Purdue University Research Computing (RCAC)](https://www.rcac.purdue.edu/)
on top of Open OnDemand, which is supported by NSF awards 1534949, 1835725,
2138286, 2303692, and 2411375.
