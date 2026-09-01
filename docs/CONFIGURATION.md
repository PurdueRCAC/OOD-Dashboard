# Configuration

Every site-specific value is configuration — **you should not need to edit any
view or controller.** `.env.local.example` is the annotated master list; it uses
"Demo" cluster as a worked example, so replace those values with your
own.

Every key is optional. A feature whose configuration is missing hides itself or
reports `N/A` rather than erroring, so an unconfigured deployment boots and
behaves like the stock dashboard.

- [Where to put configuration](#where-to-put-configuration)
- [Branding](#branding)
- [Documentation links](#documentation-links)
- [Announcements](#announcements)
- [Storage widget](#storage-widget)
- [Accounts and Balance widgets](#accounts-and-balance-widgets)
- [Stock OOD warning banners](#stock-ood-warning-banners)
- [Partitions](#partitions)
- [Cluster Status](#cluster-status)
- [GPU-hour accounting](#gpu-hour-accounting)
- [Per-job efficiency metrics](#per-job-efficiency-metrics)
- [Support tickets](#support-tickets)
- [Where the keys live in code](#where-the-keys-live-in-code)

## Where to put configuration

Each key can be set three ways, in precedence order:

1. `OOD_<KEY>` in the environment (including `/etc/ood/config/apps/dashboard/env`)
2. the key without the `OOD_` prefix in `/etc/ood/config/apps/dashboard/*.yml`
3. `.env.local` in the app directory — **development only**

For production, prefer `/etc/ood/config/apps/dashboard/`, so your configuration
lives outside the checkout and survives upgrades.

## Branding

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_SITE_NAME` | Short cluster/service name, used throughout the UI | OOD dashboard title |
| `OOD_SITE_LOGO_URL` | Logo beside the site name in the sidebar | none (text only) |

## Documentation links

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

## Announcements

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_NEWS_FEED_URL` | JSON news endpoint; unset disables the widget | none |
| `OOD_NEWS_FEED_RESOURCE_FILTER` | Keep only articles tagged with this resource name | keep all |
| `OOD_NEWS_PAGE_URL` | Human-facing archive, linked as *View All* | none |
| `OOD_NEWS_TYPE_IDS` | Comma-separated `newstypeid` values to keep; empty keeps every article | `1,2,3,6,7` |

The widget expects the response shape produced by Purdue RCAC's news API: a
`data` array whose entries carry `headline`, `uri`, `formattedbody`,
`datetimenews`, `datetimenewsend`, `newstypeid`, and optional `updates` and
`resources`.

The default `OOD_NEWS_TYPE_IDS` matches that API's taxonomy — 1 Outages and
Maintenance, 2 Announcements, 3 Science Highlights, 6 Outages, 7 Maintenance.
If your feed numbers its types differently, set your own ids; if it has no type
concept, set the key to an empty string to keep everything.

> **If your news system uses a different response shape**, `app/controllers/api/
> news_feed_controller.rb` is the one file you will need to adapt — it is the
> only place the feed format is assumed. Article *types*, though, are now
> configuration rather than a constant in that file.

Article bodies are sanitized against a tag allow-list, and article links are
restricted to `http`/`https`, before anything reaches the browser.

## Storage widget

Driven by a command you supply, since no portable way to query quotas exists.
Unset, the widget is absent.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_QUOTA_COMMAND` | Command reporting quotas, given the username as its only argument | none (widget hidden) |
| `OOD_QUOTA_COMMAND_SKIP_LINES` | Header rows to skip before the first data row | `3` |
| `OOD_SCRATCH_DIR_TEMPLATE` | Scratch path for `scratch`-type rows; `$USER` is expanded | `/<type>/<location>` |
| `OOD_HOME_DIR_TEMPLATE` | Home path for `home`-type rows; `$USER` is expanded | the PUN's `$HOME` |

Its output must be whitespace-separated columns, after the skipped header rows:

```
type     location            disk_used disk_limit disk_pct files   file_limit file_pct
home     /home/alice         38.2GB    100GB      38%      412031  1000000    41%
scratch  /scratch/alice      1.4TB     5TB        28%      883122  2000000    44%
```

`demo/bin/myquota` is a working example.

## Accounts and Balance widgets

These read Slurm accounting directly. Slurm records a balance under a TRES name
that depends on what the allocation is denominated in, and sites tell those
apart by account naming.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_GPU_ACCOUNT_PATTERN` | Regex matching GPU-denominated account names | none (all accounts read as CPU) |
| `OOD_GPU_ACCOUNT_TRES` | TRES holding the balance for matching accounts | `gres/gpu` |
| `OOD_CPU_ACCOUNT_TRES` | TRES holding the balance for all other accounts | `cpu` |
| `OOD_CPU_CAPACITY_TRES` | TRES holding CPU *capacity* (GrpTRES), not balance | `cpu` |
| `OOD_BALANCE_UNIT_LABEL` | What the balance figure is denominated in, for display | `GPU hours` |

Balance and capacity are separate axes. The three TRES keys above read an
allocation's **balance** from Slurm's `GrpTRESMins`; `OOD_CPU_CAPACITY_TRES`
reads its **CPU capacity** from `GrpTRES`. Stock Slurm reports capacity as
`cpu`; set this only if your site meters a derived resource under its own TRES
name (Purdue RCAC uses `gres/hp_cpu`).

A TRES your scheduler does not report is treated as "not available" and the
figure is omitted, rather than erroring.

`OOD_BALANCE_UNIT_LABEL` is display only — it does not change which TRES is
read. Set it to match what your billing TRES actually denominates, e.g. `SUs`
or `core-hours`.

> Prefer `"-gpu$"` over `"-gpu\z"`: unquoted, `\z` is parsed as a literal `z`
> and matches nothing. An invalid regex is logged and treated as no pattern.
>
> Set the pattern wrong and GPU allocations are reported as CPU ones silently,
> with plausible-looking numbers — check it against your account naming.

## Stock OOD warning banners

Separate from the Storage and Accounts widgets above: these keys drive OOD's
own warning banners, which read JSON files rather than shelling out.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_QUOTA_PATH` | Colon-separated quota JSON files/URLs | none |
| `OOD_QUOTA_THRESHOLD` | Warn above this usage fraction | `0.95` |
| `OOD_BALANCE_PATH` | Colon-separated balance JSON files/URLs | none |
| `OOD_BALANCE_THRESHOLD` | Warn below this balance | `0` |

## Partitions

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_EXCLUDED_PARTITIONS` | Comma-separated partitions to hide from System Status | show all |
| `OOD_GPU_PARTITIONS` | Partitions shown with per-GPU rather than per-core usage | none |
| `OOD_WHOLENODE_PARTITIONS` | Partitions allocated whole-node, where per-core usage is not meaningful | none |

Which partitions are GPU or whole-node is site policy and cannot be inferred
from the scheduler. Unset, every partition gets the generic per-core layout.

## Cluster Status

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_NODE_NAME_PATTERN` | Regex matched against node names; only matching nodes are listed | show all nodes |
| `OOD_GPU_MODELS` | Comma-separated `token:label` pairs mapping GRES tokens to readable GPU names | `l40:Nvidia L40,h100:Nvidia H100,h200:Nvidia H200` |

Leave `OOD_NODE_NAME_PATTERN` unset and every node the scheduler reports is
listed — the right default for a site whose naming this app has not seen. Set
it to hide login, service, or reservation-only nodes, e.g.
`\A(cn|gpu)-\d+\z`.

> If the pattern matches none of the reported nodes, or will not compile, that
> is written to the log rather than silently producing an empty page. An
> uncompilable pattern is treated as unset.

`OOD_GPU_MODELS` maps whatever token your `Gres` field carries — `a100`,
`mi300` — to a display name. A token with no mapping is shown as-is rather than
left blank, so an unconfigured site still shows something truthful.

## GPU-hour accounting

GPU-hour charging is site policy. Leave `OOD_GPU_HOURS_PARTITIONS` unset and all
jobs report GPU hours as `N/A` — correct for sites that do not charge separately
for GPU time.

| Key | Description | Default |
|-----|-------------|---------|
| `OOD_GPU_HOURS_PARTITIONS` | Comma-separated partitions charged for GPU hours | none (feature off) |
| `OOD_GPU_HOURS_MIN_JOB_ID` | Jobs at or below this id predate the policy and report `N/A` | `0` |
| `OOD_GPU_HOURS_DISCOUNTED_QOS` | A QoS charged at a reduced rate | none |
| `OOD_GPU_HOURS_DISCOUNTED_CHARGE_FACTOR` | Multiplier for that QoS | `0.25` |

## Per-job efficiency metrics

Both keys must be set for the utilization and memory-efficiency columns to
appear; unset, they are omitted.

| Key | Description |
|-----|-------------|
| `OOD_JOBSTATS_PYTHON` | Interpreter that has [jobstats](https://github.com/PrincetonUniversity/jobstats)' dependencies |
| `OOD_JOBSTATS_SCRIPT` | Path to the `jobstats` script |

jobstats ships a `#!/usr/bin/env python3` shebang, which on a PUN host often
resolves to an interpreter without its `requests` dependency. Rather than
executing the script directly, the dashboard invokes it as an argument to the
interpreter you name here, so its local imports still resolve.

## Support tickets

Uses OOD's standard `support_ticket` configuration in
`/etc/ood/config/apps/dashboard/*.yml` — email and Request Tracker (RT) backends
are supported. See the
[OOD support ticket docs](https://osc.github.io/ood-documentation/latest/customizations.html#support-ticket-form).

## Where the keys live in code

- `config/configuration_singleton.rb` — `site_string_configs` defines the keys
  and their defaults, and reads them from environment or config file. Keys that
  need post-processing (comma-separated lists, the `token:label` GPU map, the
  compiled node-name regex) are read there too but surfaced by named methods
  such as `gpu_partitions`, `gpu_model_map` and `node_name_regexp`.
- `app/helpers/application_helper.rb` — view-facing helpers, including the
  documentation-link fallbacks.
- `app/views/shared/_docs_info_link.html.erb` — the per-widget info icon, which
  renders nothing when no URL is configured.
