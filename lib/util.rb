require "open3"
require "set"

module Util
  def self.to_bytes(value)
    return 0 if value.nil? || value.empty?

    case value[-1]
    when "K"
      value.to_f * 1024
    when "M"
      value.to_f * 1024 * 1024
    when "G"
      value.to_f * 1024 * 1024 * 1024
    when "T"
      value.to_f * 1024 * 1024 * 1024 * 1024
    when "P"
      value.to_f * 1024 * 1024 * 1024 * 1024 * 1024
    else
      value.to_f
    end
  end

  def self.from_bytes(bytes)
    # Convert string to float if needed
    bytes = bytes.to_f if bytes.is_a?(String)
    
    return "0" if bytes.nil? || bytes.zero?
    
    units = ["B", "K", "M", "G", "T", "P"]
    unit_index = 0
    
    while bytes >= 1024 && unit_index < units.length - 1
      bytes /= 1024.0
      unit_index += 1
    end
    
    # Format with up to 2 decimal places, remove trailing zeros
    formatted = format("%.2f", bytes).sub(/\.?0+$/, "")
    "#{formatted}#{units[unit_index]}"
  end

  def self.seconds_to_timestr(total_seconds, format = nil)
    # Convert string to float if needed
    total_seconds = total_seconds.to_f if total_seconds.is_a?(String)
    
    return "-1" if total_seconds.nil? || total_seconds < 0
    
    # Round to whole seconds
    total_seconds = total_seconds.round
    
    # Auto-detect format if not specified
    format ||= (total_seconds >= 86400) ? :d_hhmmss : :hhmmss
    
    case format
    when :d_hhmmss
      days, remainder = total_seconds.divmod(86400)
      hours, remainder = remainder.divmod(3600)
      minutes, seconds = remainder.divmod(60)
      
      "%d-%02d:%02d:%02d" % [days, hours, minutes, seconds]
      
    when :hhmmss
      hours, remainder = total_seconds.divmod(3600)
      minutes, seconds = remainder.divmod(60)
      
      "%02d:%02d:%02d" % [hours, minutes, seconds]
    else
      "-1"
    end
  end

  def self.timestr_to_seconds(timestr)
    d_hhmmss_regex = /\A\d+-\d{2}:\d{2}:\d{2}\z/
    hhmmss_regex = /\A\d{2}:\d{2}:\d{2}\z/
    mmss_ms_regex = /\A\d{2}:\d{2}\.\d{3}\z/

    if d_hhmmss_regex.match?(timestr)
      parts = timestr.split("-")
      days = parts.first.to_i
      hours, minutes, seconds = parts.last.split(":").map(&:to_i)
      total_seconds = days * 86400 + hours * 3600 + minutes * 60 + seconds
    elsif hhmmss_regex.match?(timestr)
      hours, minutes, seconds = timestr.split(":").map(&:to_i)
      total_seconds = hours * 3600 + minutes * 60 + seconds
    elsif mmss_ms_regex.match?(timestr)
      minutes, seconds_milliseconds = timestr.split(":")
      seconds, milliseconds = seconds_milliseconds.split(".")
      total_seconds = ((minutes.to_i * 60) + seconds.to_i + (milliseconds.to_i / 1000.0)).round
    else
      return -1
    end

    return total_seconds
  end

  def self.timestamp_to_epoch(timestamp)
    return "N/A" if timestamp.nil? || timestamp == "(null)" || timestamp == "None" || timestamp == "N/A" || timestamp.empty?

    begin
      result = if timestamp.include?('T')
        Time.strptime(timestamp, "%FT%T").to_i
      else
        Time.parse(timestamp).to_i
      end
      result
    rescue ArgumentError => e
      "N/A"
    end
  end

  # Based on jobsu script
  #
  # GPU-hour accounting rules are site policy, so which partitions are charged,
  # which job ids predate the policy, and which QoS gets a discount all come
  # from configuration. A site that charges nothing leaves
  # `gpu_hours_partitions` unset and every job reports "N/A".
  def self.get_gpu_hours_usage(jobid, partition, qos, used_seconds, timelimit, reqtres)
    charged_partitions = Configuration.gpu_hours_partitions
    return ["N/A", "N/A"] unless charged_partitions.include?(partition)

    # Jobs submitted before the policy took effect are exempt.
    min_job_id = Configuration.gpu_hours_min_job_id.to_i
    return ["N/A", "N/A"] if jobid.partition(/\D/).first.to_i <= min_job_id

    discounted_qos = Configuration.gpu_hours_discounted_qos
    charge_factor = if discounted_qos.present? && qos == discounted_qos
                      Configuration.gpu_hours_discounted_charge_factor.to_f
                    else
                      1
                    end
    used_hours = used_seconds / 3600.to_f
    reserved_hours = timelimit / 3600.to_f
    req_tres_hash = reqtres.split(",").map { |pair| pair.split("=") }.to_h
    reserved_gpus = req_tres_hash["gres/gpu"].to_i

    total_used_gpu_hours = reserved_gpus * used_hours * charge_factor
    total_gpu_hours = reserved_gpus * reserved_hours * charge_factor

    return [total_used_gpu_hours, total_gpu_hours]
  end

  # jobstats' own shebang is `#!/usr/bin/env python3`, which on the OOD PUN
  # host often resolves to an interpreter without the `requests` module the
  # tool needs. So rather than executing the script directly, sites configure
  # both an interpreter that has jobstats' dependencies
  # (`OOD_JOBSTATS_PYTHON`) and the script path (`OOD_JOBSTATS_SCRIPT`), and we
  # invoke the script as an argument to that interpreter so its local imports
  # still resolve. Unset either one and job metrics are simply not collected.
  JOBSTATS_TIMEOUT_SECONDS = 8

  # Run jobstats for a raw job id and return the parsed JSON hash, cached 45s,
  # or nil if jobstats/Prometheus is unavailable. No GPU/started guards here,
  # so this is the entry point used by the My Jobs batch endpoint (which has
  # already narrowed to GPU jobs client-side).
  def self.run_jobstats(job_id)
    return nil unless Configuration.jobstats_enabled?
    return nil if job_id.nil? || job_id.to_s.empty?
    return nil unless /\A\d+(_\d+)?\z/.match?(job_id.to_s)

    Rails.cache.fetch("jobstats/#{job_id}", expires_in: 45.seconds) do
      base_job_id = job_id.to_s.split("_").first
      # Clear PYTHONHOME/PYTHONPATH the PUN/Passenger process may set, so the
      # bundled interpreter finds its own stdlib. PATH stays inherited so
      # jobstats can still locate sacct/scontrol.
      stdout, stderr, status = Open3.capture3(
        { "PYTHONHOME" => nil, "PYTHONPATH" => nil },
        "timeout", "#{JOBSTATS_TIMEOUT_SECONDS}s",
        Configuration.jobstats_python, Configuration.jobstats_script, "-j", base_job_id
      )

      unless status.success?
        Rails.logger.info("jobstats unavailable for job #{base_job_id}: #{stderr.strip}")
        next nil
      end

      JSON.parse(stdout)
    end
  rescue StandardError => e
    Rails.logger.info("Failed to fetch jobstats for job #{job_id}: #{e.message}")
    nil
  end

  # Single-job-page path: skip the shell-out entirely for non-GPU or
  # not-yet-started jobs, then delegate to run_jobstats.
  def self.fetch_jobstats(data)
    return nil unless data["AllocTRES"]&.include?("gres/gpu=")
    return nil unless data["Start"]
    return nil unless data["JobID"]

    run_jobstats(data["JobID"])
  end

  # Average GPU duty-cycle utilization as a 0-1 fraction. nil if unavailable.
  # Matches jobstats' overall utilization: mean of every per-GPU value.
  def self.gpu_utilization_from(parsed)
    return nil unless parsed
    utilizations = parsed["nodes"].to_h.values.flat_map { |node| node["gpu_utilization"].to_h.values }
    return nil if utilizations.empty?
    (utilizations.sum / utilizations.size.to_f) / 100.0
  rescue StandardError
    nil
  end

  # GPU memory usage as a 0-1 fraction. nil if unavailable. Total peak used /
  # total capacity, summed across all GPUs and nodes.
  def self.gpu_memory_efficiency_from(parsed)
    return nil unless parsed
    nodes = parsed["nodes"].to_h.values
    used  = nodes.flat_map { |node| node["gpu_used_memory"].to_h.values }.sum
    total = nodes.flat_map { |node| node["gpu_total_memory"].to_h.values }.sum
    return nil if total.zero?
    used.to_f / total
  rescue StandardError
    nil
  end

  def self.gpu_utilization(data)
    gpu_utilization_from(fetch_jobstats(data))
  end

  def self.gpu_memory_efficiency(data)
    gpu_memory_efficiency_from(fetch_jobstats(data))
  end

  def self.scontrol_to_hash(output)
    return output.split("\n").map { |line| 
      line.scan(/(?:(?<=\A|\s))([^\s=]+)=((?:(?!\s(?:\S+)=).)*)/).to_h.transform_values(&:strip)
    }.delete_if(&:empty?)
  end

  def self.get_user_allocations(user)
    allocations = Rails.cache.fetch("allocations/#{user}", expires_in: 1.days) do
      # No shell: the `| xargs | tr ' ' ',' | tr -d '\n'` pipeline just collapsed
      # the one-account-per-line output into a comma-separated list, which
      # `split.join(",")` does directly.
      output, status = Open3.capture2e(
        "sacctmgr", "show", "user", user.to_s, "withassoc", "format=account", "-P", "-n", "-r"
      )

      if status.success?
        output.split.join(",")
      else
        return false
      end
    end

    return allocations
  end
end