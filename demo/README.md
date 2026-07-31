# Demo mode

Run the dashboard with no cluster behind it, so people can click through every
page and decide whether they want it deployed.

```bash
OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000
# then open http://localhost:3000
```

A dark banner across the top marks every page as demo data.

## What you can click through

| Page | What the demo shows |
|------|---------------------|
| Dashboard home | Announcements, job queue, System Status, Accounts, Storage widgets |
| Cluster Status | 82 nodes across five families, mixed IDLE/MIXED/ALLOCATED/DRAIN/DOWN states |
| Node detail | Per-node CPU, memory, GPU model and the jobs running on it |
| My Jobs | 250 jobs over 60 days — date range filtering, column filters, state and GPU-hour charts, CSV/XLSX export |
| Job detail | Full `sacct`/`scontrol` fields, efficiency metrics, Cancel button |
| Performance Metrics | Aggregate efficiency trends for the demo user |
| Dashboard Guide | The in-portal help page |

Populated with: 7 partitions, 82 nodes (including L40 and H100 GPU nodes), 250
jobs across 6 states, 4 allocations (one GPU-denominated), 4 filesystems, 6
announcements including a live outage and an upcoming maintenance window.

## How it works

Demo mode swaps the scheduler at the **process boundary**, not in application
code. `config/initializers/demo_mode.rb` prepends `demo/bin` to `PATH`, where
stub executables stand in for the real tools:

```
demo/bin/sinfo  squeue  sacct  sacctmgr  scontrol  scancel  myquota  jobstats
demo/lib/demo_cluster.rb     one seeded, self-consistent fake cluster
demo/fixtures/news.json      announcements feed
demo/fixtures/motd.md        message of the day
```

`motd.md` is configured but not shown: this fork's dashboard does not place the
MOTD widget on its home page. It exists because `MotdFile` logs a warning on
every request when no path is set, which reads like a fault in a demo people
are inspecting. Sites that do render the widget get a working example.

Every stub reads the same `demo_cluster.rb` dataset, so the nodes `sinfo`
summarises are the nodes `scontrol` lists, and the jobs `squeue` shows are the
jobs `sacct` reports. The data is generated from a fixed seed, so the demo looks
identical on every run — good for screenshots — while timestamps stay relative
to now, so nothing looks stale.

Because nothing in `app/` or `lib/` knows demo mode exists, **the code paths
being exercised are the production ones**, just pointed at invented data. That
also means demo mode cannot change behaviour when it is off: no `PATH` entry, no
injected configuration, no banner.

The initializer also fills in site configuration defaults (site name, doc links,
GPU-hour rules, jobstats paths) so no widget is empty. Anything you set yourself
still wins.

## Containers

### Apptainer (recommended on HPC)

```bash
apptainer build --ignore-fakeroot-command dashboard-demo.sif demo/apptainer.def
apptainer run --cleanenv dashboard-demo.sif
# open http://localhost:3000
```

Built and run end to end on a Slurm login node: unprivileged build, all pages
and API endpoints serving, Files app included.

Two things about running it that are easy to trip over:

**Use `--cleanenv`.** Apptainer passes the host environment into the container,
and HPC login nodes commonly export `LD_PRELOAD` for XALT job tracking, pointing
at host libraries built against a different glibc. That kills every binary in
the container before any of its own code runs, so the image cannot defend
against it from the inside — you get only
`libc.so.6: version 'GLIBC_2.34' not found` and no server. `--cleanenv` fixes it.

**Pass `PORT` as `APPTAINERENV_PORT`,** since `--cleanenv` also drops your own
variables:

```bash
APPTAINERENV_PORT=8080 apptainer run --cleanenv dashboard-demo.sif
```

Build notes: `--fakeroot` works if you are listed in `/etc/subuid`; if not,
`--ignore-fakeroot-command` lets Apptainer map you to root in a user namespace,
which is enough. The recipe deliberately avoids `apt` — the base image already
carries Ruby and a toolchain, and Node arrives as an official tarball — because
package installs are the step most likely to fail without real fakeroot.

The image is ~580 MB and takes roughly ten minutes to build.

### Docker

```bash
docker build -f demo/Dockerfile -t ood-hpc-dashboard:demo .
docker run --rm -p 3000:3000 ood-hpc-dashboard:demo
```

It mirrors the Apptainer recipe: same sibling-app layout, same gem install,
same runtime environment. The one deliberate difference is that it installs
Node with `apt`, which is fine because a Docker build genuinely runs as root.

> **The image has never been built** — no container runtime was available where
> it was written, whereas the Apptainer recipe was built and run. What *is*
> verified on every change: that each `COPY` source and every file the build
> references exists, and that the exact runtime environment it sets boots the
> app with all pages and endpoints serving. The untested part is the build
> itself. If it needs a fix, the `rails server` command above gives the
> identical demo.

A `.dockerignore` keeps the git history, `node_modules`, stale compiled assets
and any local `.env` out of the build context — the last of those would
otherwise bake site configuration, or secrets, into the image.

## Refreshing the announcements

```bash
ruby demo/fixtures/generate_news.rb
```

Re-anchors the outage and maintenance windows to the current date.

## Limitations

- **Launching interactive apps does not work.** That needs a real OOD portal and
  a real scheduler; the demo only fakes the monitoring data sources.
- **The containers browse the container's filesystem, not the cluster's.** The
  Files app is enabled and works, but it sees whatever the container sees --
  your home directory is bind-mounted by Apptainer, nothing else is.
- **Cancel Job succeeds but changes nothing** — the dataset is read-only, so the
  job is still listed afterwards.
- **No authentication.** Demo mode does not add or bypass any; run it locally,
  not on a public address.
- **Not for production.** It is opt-in via `OOD_DEMO_MODE`, logs a warning on
  boot, and banners every page, but it should never be enabled on a real portal.
