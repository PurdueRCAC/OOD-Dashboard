module Api
  class JobQueueController < ApplicationController
    def get
      squeue = Rails.cache.fetch("squeue", expires_in: 5.seconds) do
        output = `squeue -t all -h -o "%i|%P|%j|%u|%T|%r|%V|%S|%e"`
  
        if $?.success?
          jobs = output.split("\n").map { |job|
            s = job.split("|")
            {
              jobid: s[0],
              partition: s[1],
              name: s[2],
              user: s[3],
              state: s[4],
              reason: s[5],
              submit_time: s[6],
              start_time: s[7],
              end_time: s[8]
            }
          }
          jobs
        else
          return []
        end
      end

      if squeue
        filtered_jobs = squeue
          .select { |job| job[:user] == @user.name }
          .sort_by { |job| job[:jobid] }
          .reverse
          .take(200)
        
        render json: filtered_jobs.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
