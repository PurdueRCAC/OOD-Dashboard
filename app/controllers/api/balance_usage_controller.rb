require "open3"

module Api
  class BalanceUsageController < ApplicationController
    def get
      user = @user.name

      allocations = Util.get_user_allocations(user)
      # The TRES config participates in the key so that changing it takes effect
      # immediately rather than after the hour-long cache expires.
      cache_key = ["balance_usage", user, ::Configuration.gpu_account_pattern,
                   ::Configuration.gpu_account_tres, ::Configuration.cpu_account_tres].join("/")
      mybalance = Rails.cache.fetch(cache_key, expires_in: 1.hours, race_condition_ttl: 3.seconds) do
        # No shell: `| tail -n +3` skipped the two header lines, which
        # `lines.drop(2)` does directly.
        raw_output, scontrol_status = Open3.capture2e(
          "scontrol", "show", "assoc", "users=#{user}", "accounts=#{allocations}", "flags=assoc", "-o"
        )
        output = raw_output.lines.drop(2).join

        if scontrol_status.success?
          parsed_data = Util.scontrol_to_hash(output)
          parsed_data.select { |line_h| line_h["UserName"].blank? }.map { |line_h|
            grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
            tres_key = ::Configuration.account_tres_for(line_h["Account"])
            data = grp_tres_mins[tres_key]
            
            # Get user's specific usage for this account
            user_line = parsed_data.find { |l| 
              l["UserName"]&.match?(/^#{Regexp.escape(user.to_s)}(\(\d+\))?$/) && 
              l["Account"] == line_h["Account"] 
            }
            user_tres_mins = user_line ? user_line["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h : {}
            user_data = user_tres_mins[tres_key]
            user_usage = user_data&.match(/(\d+|N)\((\d+)\)/)&.[](2).to_f / 60 rescue 0
            
            data.match(/(\d+|N)\((\d+)\)/) { |m| 
              { 
                account: line_h["Account"], 
                used: m[2].to_f / 60,
                user_used: user_usage,
                limit: m[1].to_f.positive? ? m[1].to_f / 60 : "No limit"
              } 
            }
          }.sort_by { |hash| hash[:account] }
        else
          return false
        end
      end

      if mybalance
        render json: mybalance.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
