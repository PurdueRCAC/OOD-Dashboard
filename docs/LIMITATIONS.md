# Known Limitations

Read this before deploying to production. Installing this app replaces the
dashboard your users see.

## Scope and maintenance

- **Slurm only.** The monitoring features parse Slurm command output. Other
  schedulers lose those pages, though app launching still works.
- **Replaces the dashboard.** This is a fork of the OOD dashboard, not an app
  installed alongside it. Deploying it as the system dashboard means you are
  maintaining a fork: OOD dashboard updates must be merged in rather than
  applied by upgrading OOD.
- **Forked from OOD 3.x / Rails 6.1.** It has not been rebased onto newer
  upstream dashboard releases.
- **Only tested on RHEL 9 with Slurm.** Other combinations are untested.

## Features that need site-local work

- **The news feed format is site-specific.** Only Purdue RCAC's news API shape
  is implemented; other news systems require adapting
  `app/controllers/api/news_feed_controller.rb`.
- **The Storage widget needs a quota command you supply.** There is no portable
  way to ask a cluster for quotas, so `OOD_QUOTA_COMMAND` names a site-local
  wrapper and the widget parses its columns. Without one the widget is absent
  rather than broken, but you get no storage reporting until you write it.
- **The Accounts widget still assumes two TRES names.** `OOD_GPU_ACCOUNT_TRES`
  and `OOD_CPU_ACCOUNT_TRES` cover the balance figures, but the live core counts
  in `api/account_list_controller.rb` still read the `gres/hp_cpu` and `billing`
  TRES directly. Sites that do not define those will see that widget fail.

## Testing

| Site | OOD Version | Scheduler | Status |
|------|-------------|-----------|--------|
| Purdue RCAC (Gautschi) | 3.1 | Slurm | In production |

**There is no automated test suite.** The upstream dashboard's tests were not
carried over into this fork, so `bin/rails test` runs zero tests. Changes are
verified manually against a sandbox deployment using the checklist in
[Installation → Verify](INSTALLATION.md#4-verify), plus `demo/smoke.sh`.
Restoring upstream's test suite is an open task and a welcome contribution.
