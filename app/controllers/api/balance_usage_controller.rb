module Api
  class BalanceUsageController < ApplicationController
    def get
      user = @user.name

      allocations = Util.get_user_allocations(user)
      mybalance = Rails.cache.fetch("balance_usage/#{user}", expires_in: 1.hours, race_condition_ttl: 3.seconds) do
        output = `scontrol show assoc users=#{user} accounts=#{allocations} flags=assoc -o | tail -n +3`

        if $?.success?
          parsed_data = Util.scontrol_to_hash(output)
          parsed_data.select { |line_h| line_h["UserName"].blank? }.map { |line_h|
            grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
            data = line_h["Account"].end_with?("-gpu") ? grp_tres_mins["gres/gpu"] : grp_tres_mins["cpu"]
            
            # Get user's specific usage for this account
            user_line = parsed_data.find { |l| 
              l["UserName"]&.match?(/^#{Regexp.escape(user.to_s)}(\(\d+\))?$/) && 
              l["Account"] == line_h["Account"] 
            }
            user_tres_mins = user_line ? user_line["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h : {}
            user_data = line_h["Account"].end_with?("-gpu") ? user_tres_mins["gres/gpu"] : user_tres_mins["cpu"]
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
