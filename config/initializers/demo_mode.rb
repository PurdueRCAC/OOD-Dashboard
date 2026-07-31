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

    {
      'OOD_SITE_NAME'                => 'Demo Cluster',
      'OOD_DASHBOARD_DOCS_URL'       => 'https://osc.github.io/ood-documentation/latest/',
      'OOD_DASHBOARD_SUPPORT_URL'    => 'https://discourse.openondemand.org/',
      'OOD_DOCS_ACCOUNTS_URL'        => 'https://slurm.schedmd.com/accounting.html',
      'OOD_DOCS_PARTITIONS_URL'      => 'https://slurm.schedmd.com/sinfo.html',
      'OOD_DOCS_STORAGE_URL'         => 'https://osc.github.io/ood-documentation/latest/',
      'OOD_DOCS_NODES_URL'           => 'https://slurm.schedmd.com/scontrol.html',

      # Served from a local fixture rather than an HTTP endpoint.
      'OOD_NEWS_FEED_URL'            => Rails.root.join('demo', 'fixtures', 'news.json').to_s,
      'OOD_NEWS_PAGE_URL'            => 'https://openondemand.org/',

      'OOD_SCRATCH_DIR_TEMPLATE'     => '/scratch/demo/$USER',

      # Stubbed by demo/bin/myquota, which emits three header lines.
      'OOD_QUOTA_COMMAND'            => 'myquota',
      'OOD_QUOTA_COMMAND_SKIP_LINES' => '3',

      # The demo's "vision-gpu" allocation is denominated in GPU minutes.
      'OOD_GPU_ACCOUNT_PATTERN'      => '-gpu\z',

      # Charge the two GPU partitions, with no historical cutoff, so the GPU
      # hour columns and charts are populated.
      'OOD_GPU_HOURS_PARTITIONS'     => 'ai,gpu',
      'OOD_GPU_HOURS_MIN_JOB_ID'     => '0',
      'OOD_GPU_HOURS_DISCOUNTED_QOS' => 'preemptible',

      # The stub jobstats is a self-contained executable on the demo PATH, so
      # "interpreter + script" resolves to `env jobstats`.
      'OOD_JOBSTATS_PYTHON'          => '/usr/bin/env',
      'OOD_JOBSTATS_SCRIPT'          => 'jobstats'
    }.each { |key, value| ENV[key] ||= value }

    Rails.logger.warn('[demo mode] Serving invented cluster data from demo/bin. Do not use in production.')
    warn('[demo mode] Serving invented cluster data from demo/bin. Do not use in production.')
  else
    warn("[demo mode] OOD_DEMO_MODE is set but #{demo_bin} is missing; running against the real scheduler.")
  end
end
