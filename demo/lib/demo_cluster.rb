# frozen_string_literal: true

# Deterministic fake cluster used by the demo-mode stub scheduler tools in
# demo/bin. Every stub requires this file, so they all describe one consistent
# cluster: the nodes sinfo summarises are the nodes scontrol lists, and the jobs
# squeue shows are the jobs sacct reports.
#
# Everything is generated from a fixed seed, so the demo looks the same on every
# run and screenshots stay reproducible. Times are relative to "now" so the data
# never goes stale.
module DemoCluster
  SEED = 20260730

  # The demo runs as whoever started it; jobs are attributed to that account so
  # the "my jobs" and job queue filters actually match something.
  def self.me
    ENV['USER'] || ENV['LOGNAME'] || 'demo'
  end

  OTHER_USERS = %w[bmartin cwong dpatel efischer].freeze

  # Accounts. One deliberately ends in "-gpu", because the balance widgets treat
  # that suffix as meaning the allocation is measured in GPU-minutes -- the demo
  # should exercise both branches.
  # `cores` / `cores_running` feed the Accounts widget's live core counts, which
  # the dashboard reads from the GrpTRES association fields.
  ACCOUNTS = [
    { name: 'phys-lab',   limit_minutes: 9_000_000, used_minutes: 5_142_000, gpu: false, cores: 4096, cores_running: 2880 },
    { name: 'chem-lab',   limit_minutes: 4_500_000, used_minutes: 4_051_800, gpu: false, cores: 2048, cores_running: 1912 },
    { name: 'cs-dept',    limit_minutes: nil,       used_minutes: 1_284_000, gpu: false, cores: 1024, cores_running: 296  },
    { name: 'vision-gpu', limit_minutes: 600_000,   used_minutes: 218_400,   gpu: true,  cores: 512,  cores_running: 184  }
  ].freeze

  PARTITIONS = %w[cpu highmem gpu ai interactive debug profiling].freeze

  # Node families. The prefix letters matter: the cluster status page only
  # displays nodes matching /\A[abghi]\d+\z/, a naming convention inherited from
  # Gautschi, so the demo uses names that satisfy it.
  NODE_FAMILIES = [
    { prefix: 'a', count: 48, cpus: 128, mem_mb: 257_000,   partitions: 'cpu,debug',   gres: nil,          gpus: 0 },
    { prefix: 'b', count: 12, cpus: 128, mem_mb: 1_031_000, partitions: 'highmem',     gres: nil,          gpus: 0 },
    { prefix: 'g', count: 12, cpus: 64,  mem_mb: 515_000,   partitions: 'gpu',         gres: 'gpu:l40:4',  gpus: 4 },
    { prefix: 'h', count: 6,  cpus: 96,  mem_mb: 773_000,   partitions: 'ai',          gres: 'gpu:h100:8', gpus: 8 },
    { prefix: 'i', count: 4,  cpus: 32,  mem_mb: 128_000,   partitions: 'interactive', gres: nil,          gpus: 0 }
  ].freeze

  JOB_NAMES = %w[
    train_resnet preprocess sweep_lr md_solvate blast_search
    fftw_bench interactive jupyter rstudio pipeline_step2
    monte_carlo align_reads render_frames tune_hparams eval_model
  ].freeze

  QOS = %w[normal normal normal preemptible standby].freeze

  def self.rng
    Random.new(SEED)
  end

  # ---------------------------------------------------------------- nodes ---

  def self.nodes
    @nodes ||= begin
      r = rng
      NODE_FAMILIES.flat_map do |fam|
        (1..fam[:count]).map do |i|
          name = format('%s%03d', fam[:prefix], i)
          roll = r.rand(100)
          state, cpu_frac = case roll
                            when 0...8   then ['IDLE', 0.0]
                            when 8...20  then ['ALLOCATED', 1.0]
                            when 20...94 then ['MIXED', r.rand(0.15..0.95)]
                            when 94...97 then ['DRAIN', 0.0]
                            else              ['DOWN*', 0.0]
                            end
          cpu_alloc = (fam[:cpus] * cpu_frac).round
          gpu_alloc = fam[:gpus].zero? ? 0 : [(fam[:gpus] * cpu_frac).round, fam[:gpus]].min
          mem_alloc = (fam[:mem_mb] * cpu_frac * 0.8).round

          {
            name: name,
            state: state,
            partitions: fam[:partitions],
            cpu_tot: fam[:cpus],
            cpu_alloc: cpu_alloc,
            cpu_load: (cpu_alloc.zero? ? 0.0 : (cpu_alloc * r.rand(0.75..1.05))).round(2),
            mem_tot: fam[:mem_mb],
            mem_alloc: mem_alloc,
            mem_free: fam[:mem_mb] - mem_alloc,
            gres: fam[:gres],
            gpu_tot: fam[:gpus],
            gpu_alloc: gpu_alloc
          }
        end
      end
    end
  end

  def self.node(name)
    nodes.find { |n| n[:name] == name }
  end

  # ----------------------------------------------------------- partitions ---

  # sinfo-style rollup, derived from the node list so the two always agree.
  def self.partition_summary
    PARTITIONS.map do |part|
      members = nodes.select { |n| n[:partitions].split(',').include?(part) }
      # Partitions with no dedicated family still need plausible numbers.
      members = nodes.first(6) if members.empty?

      alloc = members.count { |n| n[:state] == 'ALLOCATED' }
      idle  = members.count { |n| n[:state] == 'IDLE' }
      other = members.count { |n| %w[DOWN* DRAIN].include?(n[:state]) }
      mixed = members.size - alloc - idle - other

      {
        name: part,
        avail: part == 'profiling' ? 'inact' : 'up',
        nodes_alloc: alloc + mixed,
        nodes_idle: idle,
        nodes_other: other,
        nodes_total: members.size,
        cpus_alloc: members.sum { |n| n[:cpu_alloc] },
        cpus_idle: members.sum { |n| n[:cpu_tot] - n[:cpu_alloc] },
        cpus_other: members.select { |n| %w[DOWN* DRAIN].include?(n[:state]) }.sum { |n| n[:cpu_tot] },
        cpus_total: members.sum { |n| n[:cpu_tot] }
      }
    end
  end

  # ----------------------------------------------------------------- jobs ---

  STATES = [
    ['COMPLETED', 55], ['FAILED', 12], ['TIMEOUT', 6],
    ['CANCELLED', 6], ['RUNNING', 15], ['PENDING', 6]
  ].freeze

  PENDING_REASONS = ['Priority', 'Resources', 'QOSMaxJobsPerUserLimit', 'Dependency'].freeze
  FAIL_REASONS    = ['NonZeroExitCode', 'JobLaunchFailure', 'None'].freeze

  def self.jobs
    @jobs ||= begin
      r = rng
      now = Time.now
      id = 600_000

      250.times.map do
        id += r.rand(1..7)
        state = weighted(STATES, r)
        part = PARTITIONS[r.rand(PARTITIONS.size - 1)] # never 'profiling'
        gpu_part = %w[ai gpu].include?(part)
        user = r.rand(100) < 62 ? me : OTHER_USERS[r.rand(OTHER_USERS.size)]
        acct = if gpu_part && r.rand(100) < 55
                 'vision-gpu'
               else
                 ACCOUNTS[r.rand(3)][:name]
               end

        cpus = [1, 2, 4, 8, 16, 32, 64, 128][r.rand(8)]
        gpus = gpu_part ? [1, 1, 2, 4, 8][r.rand(5)] : 0
        mem_gb = [4, 8, 16, 32, 64, 128, 256][r.rand(7)]
        limit_s = [1800, 3600, 7200, 14_400, 43_200, 86_400][r.rand(6)]

        submit = now - r.rand(1..60) * 86_400 - r.rand(0..86_399)
        case state
        when 'PENDING'
          start_t = nil
          end_t = nil
          elapsed = 0
        when 'RUNNING'
          start_t = submit + r.rand(30..3600)
          elapsed = [(now - start_t).to_i, limit_s].min
          end_t = nil
        else
          start_t = submit + r.rand(30..3600)
          elapsed = state == 'TIMEOUT' ? limit_s : (limit_s * r.rand(0.05..0.98)).round
          end_t = start_t + elapsed
        end

        nodelist = if state == 'PENDING'
                     'None assigned'
                   else
                     pool = nodes.select { |n| n[:partitions].split(',').include?(part) }
                     pool = nodes if pool.empty?
                     pool[r.rand(pool.size)][:name]
                   end

        {
          id: id,
          name: JOB_NAMES[r.rand(JOB_NAMES.size)],
          user: user,
          account: acct,
          partition: part,
          qos: QOS[r.rand(QOS.size)],
          state: state,
          reason: case state
                  when 'PENDING' then PENDING_REASONS[r.rand(PENDING_REASONS.size)]
                  when 'FAILED'  then FAIL_REASONS[r.rand(FAIL_REASONS.size)]
                  else 'None'
                  end,
          submit: submit,
          start: start_t,
          end: end_t,
          elapsed: elapsed,
          timelimit: limit_s,
          cpus: cpus,
          gpus: gpus,
          mem_gb: mem_gb,
          maxrss_kb: (mem_gb * 1024 * 1024 * r.rand(0.15..0.95)).round,
          diskwrite_mb: r.rand(1..9000),
          diskread_mb: r.rand(1..9000),
          nodelist: nodelist,
          workdir: "/home/#{user}/projects/#{JOB_NAMES[r.rand(JOB_NAMES.size)]}",
          exit_code: state == 'FAILED' ? "#{r.rand(1..127)}:0" : '0:0'
        }
      end
    end
  end

  def self.job(id)
    jobs.find { |j| j[:id].to_s == id.to_s.split('.').first.split('_').first }
  end

  def self.weighted(pairs, r)
    total = pairs.sum { |(_, w)| w }
    roll = r.rand(total)
    acc = 0
    pairs.each do |(value, w)|
      acc += w
      return value if roll < acc
    end
    pairs.last.first
  end

  # ------------------------------------------------------------ formatting ---

  def self.hhmmss(seconds)
    return '00:00:00' if seconds.nil? || seconds.to_i <= 0

    s = seconds.to_i
    d = s / 86_400
    rest = s % 86_400
    core = format('%02d:%02d:%02d', rest / 3600, (rest % 3600) / 60, rest % 60)
    d.positive? ? "#{d}-#{core}" : core
  end

  def self.slurm_time(t)
    t.nil? ? 'Unknown' : t.strftime('%Y-%m-%dT%H:%M:%S')
  end
end
