module Api
  class DiskUsageController < ApplicationController
    def get
      myquota = Rails.cache.fetch("disk_usage/#{@user.name}", expires_in: 60.seconds, race_condition_ttl: 3.seconds) do
        output = `myquota #{@user.name}`

        if $?.success?
          output
        else
          return false
        end
      end

      if myquota
        render json: myquota.split("\n").drop(3).map { |line|
          s = line.split
          { type: s[0], location: s[1], disk_usage: s[2], disk_usage_limit: s[3], disk_usage_percentage: s[4], file_count: s[5], file_count_limit: s[6], file_count_percentage: s[7] }
        }.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
