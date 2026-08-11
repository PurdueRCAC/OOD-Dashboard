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
- **Only tested on several systems.** See
  [Known-good versions](INSTALLATION.md#known-good-versions) for our test results.
  Other combinations are untested.

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

This dashboard has been tested and deployed on all HPC clusters at Purdue RCAC.
See below the current in production package combinations

| Component | Cluster1 | Cluster2 | Cluster3 | Cluster4 |
| --- | --- | --- | --- | --- |
| Open OnDemand | 4.2.2 | 4.2.2 | 3.1.14 | 2.0.32 |
| OS | Rocky Linux 9.8 | Rocky Linux 9.8 | Rocky Linux 9.6 | Rocky Linux 8.10 |
| Ruby (PUN, built via rbenv) | 3.1.2 | 3.3.10 | 3.1.7 | 2.7.8 |
| Bundler | 2.3.6 | 2.3.6 | 2.3.6 | 2.3.6 |
| Rails | 6.1.7.6 | 6.1.7.6 | 6.1.7.6 | 6.1.7.6 |
| Nokogiri | 1.15.5 | 1.15.5 | 1.15.5 | 1.15.5 |
| Node.js | 18.20.8 | 18.20.8 | 18.20.8 | 18.20.8 |
| Yarn | 1.22.22 | 1.22.22 | 1.22.22 | 1.22.22 |
| Slurm | 26.05.1 | 26.05.1 | 25.05.2 | 25.11.1 |

**There is no automated test suite.** The upstream dashboard's tests were not
carried over into this fork, so `bin/rails test` runs zero tests. Changes are
verified manually against a sandbox deployment using the checklist in
[Installation → Verify](INSTALLATION.md#4-verify), plus `demo/smoke.sh`.
Restoring upstream's test suite is an open task and a welcome contribution.
