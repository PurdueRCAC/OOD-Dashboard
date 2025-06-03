require "date"
require "open3"

class MyJobsController < ApplicationController
  # first: use value in first line with jobid
  # max: use max value among all lines with jobid
  # created: value will be set afterwards
  # duration: value is a time duration
  # timestamp: value is a unix timestamp
  FIELDS = {
    "jobid" => { "prefer" => "first", "format" => "number", "formattedname" => "Job ID" },
    "jobname" => { "prefer" => "first", "format" => "string", "formattedname" => "Job Name" },
    "user" => { "prefer" => "first", "format" => "string", "formattedname" => "User" },
    "account" => { "prefer" => "first", "format" => "string", "formattedname" => "Account" },
    "start" => { "prefer" => "first", "format" => "timestamp", "formattedname" => "Start Time", "compare_fn" => Util.method(:timestamp_to_epoch) },
    "end" => { "prefer" => "first", "format" => "timestamp", "formattedname" => "End Time", "compare_fn" => Util.method(:timestamp_to_epoch) },
    "elapsed" => { "prefer" => "max", "format" => "duration", "formattedname" => "Elapsed", "compare_fn" => Util.method(:timestr_to_seconds) },
    "submit" => { "prefer" => "first", "format" => "timestamp", "formattedname" => "Submit Time", "compare_fn" => Util.method(:timestamp_to_epoch) },
    "planned" => { "prefer" => "max", "format" => "duration", "formattedname" => "Planned Time", "compare_fn" => Util.method(:timestr_to_seconds) },
    "used_gpu_hours" => { "prefer" => "created", "format" => "", "formattedname" => "GPU Hours Used" },
    "required_gpu_hours" => { "prefer" => "created", "format" => "", "formattedname" => "GPU Hours Required" },
    "timeeff" => { "prefer" => "created", "format" => "string", "formattedname" => "Time Efficiency" },
    "cpueff" => { "prefer" => "created", "format" => "string", "formattedname" => "CPU Efficiency" },
    "memeff" => { "prefer" => "created", "format" => "string", "formattedname" => "Memory Efficiency" },
    "partition" => { "prefer" => "first", "format" => "string", "formattedname" => "Partition" },
    "qos" => { "prefer" => "first", "format" => "string", "formattedname" => "QOS" },
    "state" => { "prefer" => "first", "format" => "string", "formattedname" => "State" },
    "reason" => { "prefer" => "first", "format" => "string", "formattedname" => "Reason" },
    "timelimit" => { "prefer" => "max", "format" => "duration", "formattedname" => "Timelimit", "compare_fn" => Util.method(:timestr_to_seconds) },
    "reqmem" => { "prefer" => "first", "format" => "size", "formattedname" => "Requested Memory", "compare_fn" => Util.method(:to_bytes) },
    "alloccpus" => { "prefer" => "first", "format" => "number", "formattedname" => "Allocated CPUs" },
    "totalcpu" => { "prefer" => "max", "format" => "duration", "formattedname" => "Total CPUs", "compare_fn" => Util.method(:timestr_to_seconds) },
    "workdir" => { "prefer" => "first", "format" => "string", "formattedname" => "Working Directory" },
    "sessionid" => { "prefer" => "created", "format" => "string", "formattedname" => "Session ID" },
    "requeue_count" => { "prefer" => "created", "format" => "string", "formattedname" => "Number of Requeues" },
    "maxrss" => { "prefer" => "max", "format" => "size", "formattedname" => "Max Memory Used", "compare_fn" => Util.method(:to_bytes) },
    "maxdiskwrite" => { "prefer" => "max", "format" => "size", "formattedname" => "Max Disk Write", "compare_fn" => Util.method(:to_bytes) },
    "maxdiskread" => { "prefer" => "max", "format" => "size", "formattedname" => "Max Disk Read", "compare_fn" => Util.method(:to_bytes) },
    "nodelist" => { "prefer" => "first", "format" => "string", "formattedname" => "Nodes" },
    "reqtres" => { "prefer" => "first", "format" => "string", "formattedname" => "Requested Resources" },
    "timestamp" => { "prefer" => "created", "format" => "", "formattedname" => "Timestamp" },
  }

  PREFER_MAX_FIELDS = FIELDS.select { |_, value| value["prefer"] == "max" }.keys
  SIZE_FIELDS = FIELDS.select { |_, value| value["format"] == "size" }.keys
  TIMESTAMP_FIELDS = FIELDS.select { |_, value| value["format"] == "timestamp" }.keys
  DURATION_FIELDS = FIELDS.select { |_, value| value["format"] == "duration" }.keys
  SACCT_FIELDS = FIELDS.select { |_, value| value["prefer"] != "created" }.keys

  def index
    render "my_jobs/index"
  end

  def cancel_jobs
    job_ids = params[:job_ids].split(",")

    # Warning: not passing any job ids to scancel when -u is specified will cancel all of the user's jobs
    if job_ids.empty?
      return head :bad_request
    end

    job_ids.each do |job_id|
      if !(/^\d+(_\d+)?$/.match?(job_id))
        return head :bad_request
      end
    end

    # All scancel output is in stderr instead of stdout for some reason
    result, _ = Open3.capture2e("scancel -u #{@user.name} -v #{params[:job_ids]}")

    cancelled_job_ids = result.split("\n").map { |line| $1 if line =~ /^scancel: Terminating job (\d+(?:_\d+)?)$/ }.compact

    if !cancelled_job_ids.empty?
      render json: {
        "cancelled" => cancelled_job_ids,
      }.to_h.to_json, status: :ok
    else
      head :internal_server_error
    end
  end

  def json
    use_cache = params[:use_cache] == "true"

    sacct_cache_key = "my_jobs_sacct/#{@user.name}"

    if use_cache && Rails.cache.exist?(sacct_cache_key)
      jobs_hash = Rails.cache.read(sacct_cache_key)
      return render json: jobs_hash.to_json, status: :ok
    end

    start_time = Date.today - 7.days
    end_time = DateTime.now
    
    if params[:start_time].present?
      start_time = Time.zone.parse(params[:start_time])
      if start_time.nil?
        return render json: {error: "Invalid start time."}, status: :bad_request
      end
    end

    if params[:end_time].present?
      end_time = Time.zone.parse(params[:end_time])
      if end_time.nil?
        return render json: {error: "Invalid end time."}, status: :bad_request
      end
    end

    if start_time > end_time
      return render json: {error: "Start time cannot be after end time."}, status: :bad_request
    end

    allocations = Util.get_user_allocations(@user.name)

    squeue = Rails.cache.fetch("squeue", expires_in: 1.seconds) do
      output = `squeue -t all -h -o "%i|%P|%j|%u|%T|%r"`

      if $?.success?
        jobs = output.split("\n").map { |job|
          s = job.split("|")
          {
            jobid: s[0],
            partition: s[1],
            name: s[2],
            user: s[3],
            state: s[4],
            reason: s[5]
          }
        }
        jobs
      else
        return []
      end
    end

    # This command gets all jobs in the current user's allocations
    result = `sacct -S #{start_time.strftime("%FT%T")} -E #{end_time.strftime("%FT%T")} -P -n -a -o #{SACCT_FIELDS.join(",")} -A #{allocations}`

    if $?.success?
      interactive_app_regex = %r{\A/home/#{Regexp.escape(@user.name)}/ondemand/data/sys/dashboard/batch_connect/sys/\w+/output/(?<uuid>[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\z}
      jobs = {}

      result.each_line do |line|
        s = line.strip.split "|"
        job_id = s[0].split(".")[0]

        if !jobs.has_key?(job_id)
          jobs[job_id] = FIELDS.keys.map { |field| [field, ""] }.to_h.merge(SACCT_FIELDS.zip(s).to_h)
          match_interactive_app = jobs[job_id]["workdir"].match(interactive_app_regex)
          jobs[job_id]["sessionid"] = match_interactive_app ? match_interactive_app["uuid"] : "N/A"
        else
          PREFER_MAX_FIELDS.each do |field|
            jobs[job_id][field] = [jobs[job_id][field], s[SACCT_FIELDS.index(field)]].max_by { |val| FIELDS[field]["compare_fn"].call(val) }
          end
        end
      end

      jobs_hash = jobs.values.map { |j|
        [SIZE_FIELDS, DURATION_FIELDS, TIMESTAMP_FIELDS].flatten.each do |field|
          j[field] = FIELDS[field]["compare_fn"].call(j[field])
        end

        state_match = j["state"].match(/^CANCELLED by (\d+)$/)
        unless state_match.nil?
          username = Rails.cache.fetch("user_id/#{state_match.captures[0]}") do
            `id -un #{state_match.captures[0]}`
          end

          if $?.success?
            j["state"] = "CANCELLED by #{username}"
          end
        end

        j["reason"] = squeue.find { |job| job[:jobid] == j["jobid"] && job[:state] == j["state"] }&.[](:reason) || j["reason"]

        if j["start"] != "N/A"
          j["timestamp"] = j["start"]
        elsif j["submit"] != "N/A"
          j["timestamp"] = j["submit"]
        elsif j["end"] != "N/A"
          j["timestamp"] = j["end"]
        else
          j["timestamp"] = "--"
        end

        j["timeeff"] = (j["elapsed"].to_f * 100 / j["timelimit"].to_f).round(2)
        j["cpueff"] = (j["totalcpu"].to_f * 100 / (j["alloccpus"].to_f * j["elapsed"].to_f)).round(2)
        j["memeff"] = (j["maxrss"].to_f * 100 / j["reqmem"].to_f).round(2)

        j["used_gpu_hours"], j["required_gpu_hours"] = Util.get_gpu_hours_usage(j["jobid"], j["partition"], j["qos"], j["elapsed"], j["timelimit"], j["reqtres"])

        j["reqtres"] = j["reqtres"].split(",").map do |pair|
          key, value = pair.split("=")
          [key, key == "mem" ? Util.to_bytes(value).to_i : value.to_i]
        end.to_h

        j["nodelist"] = expand_nodelist(j["nodelist"])

        if j["state"] == "REQUEUED"
          output = `scontrol show job #{j["jobid"]} -o`
          if $?.success?
            output_hash = Util.scontrol_to_hash(output)[0]
            j["requeue_count"] = output_hash["Restarts"]
          end
        end

        j
      }

      Rails.cache.write(sacct_cache_key, jobs_hash)

      render json: jobs_hash.to_json, status: :ok
    else
      head :internal_server_error
    end
  end

  private

  def expand_nodelist(value)
    return "N/A" if value.nil? || value == "(null)" || value == "None" || value == "N/A"

    nodes = []
    # Match patterns like: a[859,861-869,871-888,890-891,893,895-898,901-902,905,907,910]
    if match = value.match(/^([a-zA-Z]+)\[([\d\-,]+)\]$/)
      prefix = match[1]
      ranges = match[2].split(',')
      
      ranges.each do |range|
        if range.include?('-')
          start, finish = range.split('-').map(&:to_i)
          (start..finish).each { |n| nodes << "#{prefix}#{n}" }
        else
          nodes << "#{prefix}#{range}"
        end
      end
    else
      # Handle single node case or comma-separated nodes without ranges
      nodes = value.split(',')
    end

    nodes.join(',')
  end
end
