# Troubleshooting

## Widgets show "Failed to load"

The dashboard's monitoring endpoints shell out to Slurm. Confirm the commands
work **as the web user** on the OOD host:

```bash
sinfo -h -o '%R|%a|%F|%C'
scontrol show node --oneliner | head -1
sacct -X -u "$USER" -S now-1week -P -n | head
```

An empty `PATH` inside the PUN is the usual cause. Check
`~/ondemand/data/sys/dashboard/` and the Rails log under `log/` for the
underlying error.

## Efficiency metrics columns are missing

Expected when `OOD_JOBSTATS_PYTHON`/`OOD_JOBSTATS_SCRIPT` are unset. If they are
set, run the exact command the dashboard runs:

```bash
"$OOD_JOBSTATS_PYTHON" "$OOD_JOBSTATS_SCRIPT" -j <jobid>
```

A `ModuleNotFoundError: requests` means the interpreter you named lacks
jobstats' dependencies. Failures are logged at `info` level and the metrics are
skipped rather than surfaced as errors.

## Announcements widget is empty

Confirm `OOD_NEWS_FEED_URL` returns JSON from the OOD host, and that
`OOD_NEWS_FEED_RESOURCE_FILTER` matches a `resources[].name` in the response — a
filter that matches nothing yields an empty widget. The response is cached for
30 minutes; the cache key includes the URL and filter, so config changes take
effect immediately.

## Storage widget is absent

Expected unless `OOD_QUOTA_COMMAND` is set. If it is, run it by hand as the web
user with a username as its only argument and compare the output against the
column format in
[Configuration → Storage widget](CONFIGURATION.md#storage-widget).

## GPU hours all show "N/A"

Expected unless `OOD_GPU_HOURS_PARTITIONS` names the job's partition and the job
id is above `OOD_GPU_HOURS_MIN_JOB_ID`.

## Balances look wrong for GPU allocations

`OOD_GPU_ACCOUNT_PATTERN` is probably not matching your GPU account names, so
they are being read as CPU-denominated. Note that unquoted `\z` is parsed as a
literal `z` — prefer `"-gpu$"`. An invalid regex is logged and treated as no
pattern.

## JS changes do not appear

Run `bin/recompile_js`. Running esbuild alone leaves the Sprockets-served bundle
stale.

## The demo container will not start

On an HPC login node, `LD_PRELOAD` (XALT) leaks into the container and kills
every binary before its own code runs, giving
`libc.so.6: version 'GLIBC_2.34' not found`. Use `--cleanenv`, and pass your own
variables through as `APPTAINERENV_*`. See [demo/README.md](../demo/README.md).

## Checking everything at once

```bash
demo/smoke.sh https://ondemand.example.edu/pun/dev/dashboard
```

Requests every page and JSON endpoint, follows a real job id and node name out
of the running instance, and exits non-zero if anything fails. Against a real
deployment, an empty Storage or Accounts result means the site configuration is
not wired up.
