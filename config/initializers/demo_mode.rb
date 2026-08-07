# frozen_string_literal: true

# Demo mode: run the dashboard with no cluster behind it.
#
# Set OOD_DEMO_MODE=true and this initializer prepends demo/bin to PATH, where
# stub `sinfo`, `squeue`, `sacct`, `sacctmgr`, `scontrol`, `scancel`, `myquota`
# and `jobstats` executables serve a consistent fake cluster (see
# demo/lib/demo_cluster.rb). Nothing in app/ or lib/ knows demo mode exists --
# the substitution happens entirely at the process boundary, so the production
# code paths are the ones being exercised, just against invented data.
#
# It also fills in site configuration defaults so every widget has something to
# show. Anything you set yourself still wins: these are only applied to keys
# that are not already present in the environment.
#
# This is for evaluation and screenshots. It is opt-in, it never bypasses
# authentication, and it makes no attempt to be a fake OOD portal -- launching
# real interactive apps still needs a real cluster.

if ActiveModel::Type::Boolean.new.cast(ENV['OOD_DEMO_MODE']).present?
  demo_bin = Rails.root.join('demo', 'bin')

  if demo_bin.directory?
    ENV['PATH'] = "#{demo_bin}#{File::PATH_SEPARATOR}#{ENV['PATH']}"

    # Branding and outbound links. A site value here is harmless -- it changes
    # what the demo is called, not what it shows -- so let it win.
    {
      'OOD_SITE_NAME'                => 'Demo Cluster',
      'OOD_DASHBOARD_DOCS_URL'       => 'https://osc.github.io/ood-documentation/latest/',
      'OOD_DASHBOARD_SUPPORT_URL'    => 'https://discourse.openondemand.org/',
      'OOD_DOCS_ACCOUNTS_URL'        => 'https://slurm.schedmd.com/accounting.html',
      'OOD_DOCS_PARTITIONS_URL'      => 'https://slurm.schedmd.com/sinfo.html',
      'OOD_DOCS_STORAGE_URL'         => 'https://osc.github.io/ood-documentation/latest/',
      'OOD_DOCS_NODES_URL'           => 'https://slurm.schedmd.com/scontrol.html',
      'OOD_NEWS_PAGE_URL'            => 'https://openondemand.org/',
      'OOD_SCRATCH_DIR_TEMPLATE'     => '/scratch/demo/$USER'
    }.each { |key, value| ENV[key] ||= value }

    # Everything that decides WHICH DATA the demo renders. These must win over
    # site configuration, not defer to it. `install.sh` always writes a
    # .env.local, and dotenv loads it before this initializer runs, so with
    # `||=` a real deployment's values silently survive into demo mode: the news
    # widget queries the site's live API, the quota widget shells out to the real
    # command, and jobstats points at a script the demo PATH does not have. The
    # result is a demo that boots cleanly and shows empty or real data.
    {
      # Served from a local fixture rather than an HTTP endpoint. The filter must
      # be cleared too: the fixture's articles are tagged "Demo Cluster", and the
      # controller compares resource names for equality, so any inherited filter
      # excludes all six of them.
      'OOD_NEWS_FEED_URL'            => Rails.root.join('demo', 'fixtures', 'news.json').to_s,
      'OOD_NEWS_FEED_RESOURCE_FILTER' => '',

      # Give the message-of-the-day widget something to show. Without a path
      # MotdFile logs a warning on every request, which reads like a fault in a
      # demo people are inspecting.
      'MOTD_PATH'                    => Rails.root.join('demo', 'fixtures', 'motd.md').to_s,
      'MOTD_FORMAT'                  => 'markdown',

      # Stubbed by demo/bin/myquota, which emits three header lines.
      'OOD_QUOTA_COMMAND'            => 'myquota',
      'OOD_QUOTA_COMMAND_SKIP_LINES' => '3',

      # The demo's "vision-gpu" allocation is denominated in GPU minutes.
      'OOD_GPU_ACCOUNT_PATTERN'      => '-gpu\z',

      # Charge the two GPU partitions, with no historical cutoff, so the GPU
      # hour columns and charts are populated. Real partition names would match
      # nothing in the invented data.
      'OOD_GPU_HOURS_PARTITIONS'     => 'ai,gpu',
      'OOD_GPU_HOURS_MIN_JOB_ID'     => '0',
      'OOD_GPU_HOURS_DISCOUNTED_QOS' => 'preemptible',

      # The stub jobstats is a self-contained executable on the demo PATH, so
      # "interpreter + script" resolves to `env jobstats`.
      'OOD_JOBSTATS_PYTHON'          => '/usr/bin/env',
      'OOD_JOBSTATS_SCRIPT'          => 'jobstats'
    }.each { |key, value| ENV[key] = value }

    Rails.logger.warn('[demo mode] Serving invented cluster data from demo/bin. Do not use in production.')
    warn('[demo mode] Serving invented cluster data from demo/bin. Do not use in production.')
  else
    warn("[demo mode] OOD_DEMO_MODE is set but #{demo_bin} is missing; running against the real scheduler.")
  end
end
