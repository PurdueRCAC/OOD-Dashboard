module Api
  class GpuHourSummaryController < ApplicationController
    def get
      allocation = params[:allocation]

      user = @user.name

      allocations = Util.get_user_allocations(user)

      if !(allocations && allocations.split(",").include?(allocation))
        return :not_in_allocation
      end

      gpu_hour_summary = Rails.cache.fetch("gpu_hour_summary/#{allocation}", expires_in: 1.hours, race_condition_ttl: 3.seconds) do
        output = `scontrol show assoc accounts=#{allocation} flags=assoc -o | tail -n +3`

        if $?.success?
          # First find the limit from the account line
          account_line = Util.scontrol_to_hash(output).find { |line_h| line_h["Account"] == allocation }
          limit = if account_line
            grp_tres_mins = account_line["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
            data = grp_tres_mins["billing"]
            data.match(/(\d+|N)\((\d+)\)/) { |m| m[1].to_f.positive? ? m[1].to_f / 60 : "No limit" }
          end

          # Then process the non-blank UserName lines as before, but use the found limit
          Util.scontrol_to_hash(output).select { |line_h| !line_h["UserName"].blank? }.map { |line_h|
            grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
            data = grp_tres_mins["billing"]
            data.match(/(\d+|N)\((\d+)\)/) { |m| { 
              user: line_h["UserName"].split("(")[0],
              used: m[2].to_f / 60, 
              limit: m[1].to_f.positive? ? m[1].to_f / 60 : limit
            } }
          }.sort_by { |hash| -hash[:used] }
        else
          return false
        end
      end

      if gpu_hour_summary
        if gpu_hour_summary == :not_in_allocation
          head :forbidden
        else
          render json: gpu_hour_summary.to_json, status: :ok
        end
      else
        head :internal_server_error
      end
    end
  end
end
