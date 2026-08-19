require "open3"

module Api
  class AccountListController < ApplicationController
    def get
      user = @user.name

      allocations = Util.get_user_allocations(user)
      myaccounts = Rails.cache.fetch("account_list/#{user}", expires_in: 1.minutes, race_condition_ttl: 3.seconds) do
        # No shell: `| tail -n +3` skipped the two header lines and
        # `| awk '{$1=$1}1'` collapsed the padding `%.60a` adds, both of which
        # are done in Ruby below.
        scontrol_raw, scontrol_status = Open3.capture2(
          "scontrol", "show", "assoc", "users=#{user}", "accounts=#{allocations}", "flags=assoc", "-o"
        )
        scontrol_output = scontrol_raw.lines.drop(2).join

        squeue_raw, squeue_status = Open3.capture2(
          "squeue", "-h", "--array", "-A", allocations.to_s,
          "-t", "PENDING,REQUEUED", "-a", "-r", "-o", "%.60a|%C"
        )
        squeue_output = squeue_raw.lines.map { |line| line.split.join(" ") }.join("\n")

        if scontrol_status.success? && squeue_status.success?
          cpu_queued_sums = squeue_output.scan(/(.+?)\|(\d+)/).each_with_object(Hash.new(0)) do |(account, cpus), h|
            h[account] += cpus.to_i
          end

          parsed_data = Util.scontrol_to_hash(scontrol_output)
          parsed_data.select { |line_h| line_h["UserName"].blank? }.map { |line_h|
            grp_tres = line_h["GrpTRES"].split(",").map { |pair| pair.split("=") }.to_h
            grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h

            grp_tres_cpu_match = grp_tres["cpu"].match(/([^()]+)\((\d+)\)/)
            grp_tres_gres_hp_cpu_match = grp_tres["gres/hp_cpu"].match(/([^()]+)\((\d+)\)/)

            grp_tres_mins_billing_match = grp_tres_mins["billing"].match(/([^()]+)\((\d+)\)/)

            cpu_total = grp_tres_gres_hp_cpu_match[1].to_i
            cpu_running = grp_tres_gres_hp_cpu_match[2].to_i

            gpu_total = (grp_tres_mins_billing_match[1].to_f / 60.0)
            gpu_used = (grp_tres_mins_billing_match[2].to_f / 60.0)

            user_line = parsed_data.find { |l| 
              l["UserName"]&.match?(/^#{Regexp.escape(user.to_s)}(\(\d+\))?$/) && 
              l["Account"] == line_h["Account"] 
            }

            user_grp_tres_mins = user_line["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
            user_grp_tres_mins_billing_match = user_grp_tres_mins["billing"].match(/([^()]+)\((\d+)\)/)
            user_gpu_used = (user_grp_tres_mins_billing_match[2].to_f / 60.0)
            
            {
              account: line_h["Account"],
              cpu_total: cpu_total,
              cpu_queue: cpu_queued_sums[line_h["Account"]],
              cpu_running: cpu_running,
              gpu_used: gpu_used,
              user_gpu_used: user_gpu_used,
              gpu_total: gpu_total
            }
          }.sort_by { |hash| hash[:account] }
        else
          return false
        end
      end

      if myaccounts
        render json: myaccounts.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
