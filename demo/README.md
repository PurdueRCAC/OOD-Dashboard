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
jobs across 6 states, 4 allocations (one GPU-denominated), 4 filesystems, and 6
announcements including a live outage and an upcoming maintenance window.

## How it works

Demo mode swaps the scheduler at the **process boundary**, not in application
code. `config/initializers/demo_mode.rb` prepends `demo/bin` to `PATH`, where
stub executables stand in for the real tools:

```
demo/bin/sinfo  squeue  sacct  sacctmgr  scontrol  scancel  myquota  jobstats
demo/lib/demo_cluster.rb     one seeded, self-consistent fake cluster
demo/fixtures/news.json      announcements feed
```

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

## Container

```bash
docker build -f demo/Dockerfile -t ood-hpc-dashboard:demo .
docker run --rm -p 3000:3000 ood-hpc-dashboard:demo
```

> The `Dockerfile` was written without a container runtime available and has
> **not been executed**. Demo mode itself is tested; if the image build needs a
> fix, the `rails server` command above gives the identical demo.

## Refreshing the announcements

```bash
ruby demo/fixtures/generate_news.rb
```

Re-anchors the outage and maintenance windows to the current date.

## Limitations

- **Launching interactive apps does not work.** That needs a real OOD portal and
  a real scheduler; the demo only fakes the monitoring data sources.
- **Cancel Job succeeds but changes nothing** — the dataset is read-only, so the
  job is still listed afterwards.
- **No authentication.** Demo mode does not add or bypass any; run it locally,
  not on a public address.
- **Not for production.** It is opt-in via `OOD_DEMO_MODE`, logs a warning on
  boot, and banners every page, but it should never be enabled on a real portal.
