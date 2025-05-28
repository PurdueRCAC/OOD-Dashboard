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
  def self.get_gpu_hours_usage(partition, qos, used_seconds, timelimit, reqtres)
    if partition != 'ai'
      return ["N/A", "N/A"]
    end
    
    charge_factor = qos == "preemptible" ? 0.25 : 1
    used_hours = used_seconds / 3600.to_f
    reserved_hours = timelimit / 3600.to_f
    req_tres_hash = reqtres.split(",").map { |pair| pair.split("=") }.to_h
    reserved_gpus = req_tres_hash["gres/gpu"].to_i

    total_used_gpu_hours = reserved_gpus * used_hours * charge_factor
    total_gpu_hours = reserved_gpus * reserved_hours * charge_factor

    return [total_used_gpu_hours, total_gpu_hours]
  end

  def self.scontrol_to_hash(output)
    return output.split("\n").map { |line| 
      line.scan(/(?:(?<=\A|\s))([^\s=]+)=((?:(?!\s(?:\S+)=).)*)/).to_h.transform_values(&:strip)
    }.delete_if(&:empty?)
  end

  def self.get_user_allocations(user)
    allocations = Rails.cache.fetch("allocations/#{user}", expires_in: 1.days) do
      output = `sacctmgr show user #{user} withassoc format=account -P -n -r | xargs | tr ' ' ',' | tr -d '\n'`

      if $?.success?
        output
      else
        return false
      end
    end

    return allocations
  end
end