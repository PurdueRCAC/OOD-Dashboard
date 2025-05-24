module Api
  class NodesController < ApplicationController
    GPUS = {
      "l40" => "Nvidia L40",
      "h100" => "Nvidia H100",
      "h200" => "Nvidia H200",
    }
    def show
      node = Rails.cache.fetch("node_#{params[:name]}", expires_in: 30.seconds, race_condition_ttl: 3.seconds) do
        # Get detailed node info including state, memory, GPU
        output, status = Open3.capture2e("scontrol show node -a --oneliner -d #{params[:name]}")
        
        if status.success?
          result = Util.scontrol_to_hash(output)
          node_data = result.find { |node| node["NodeName"] == params[:name] }
          
          if node_data
            alloctres_hash = node_data["AllocTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
            cfgtres_hash = node_data["CfgTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
            node_data["gpu_info"] = {
              "allocated" => (alloctres_hash["gres/gpu"] || 0).to_i,
              "total" => (cfgtres_hash["gres/gpu"] || 0).to_i,
              "model" => GPUS[node_data["Gres"].split(":")[1]]
            }
            
            # Calculate memory per resource (CPU or GPU)
            mem_per_cpu = if node_data["AllocMem"] && node_data["CPUAlloc"] && node_data["CPUAlloc"] != "0"
              # Calculate memory per CPU in MB
              node_data["AllocMem"].to_i / node_data["CPUAlloc"].to_i
            else
              nil
            end
            
            # Get jobs running on this node
            jobs_output, jobs_status = Open3.capture2e("squeue -h -w #{params[:name]} -t all -o '%i|%j|%u|%P|%T|%M|%l|%b|%C'")
            
            if jobs_status.success?
              node_data["jobs"] = if jobs_output.strip.empty?
                []
              else
                jobs_output.split("\n").map do |job|
                  id, name, user, partition, state, time, time_limit, gres, cpus = job.strip.split("|")
                  
                  # Parse GRES (GPU) allocation from job
                  gpu_count = if gres&.match(/gpu:(\d+)/)
                    $1.to_i
                  else
                    0
                  end

                  total_memory = if mem_per_cpu
                    # Calculate memory based on CPUs for all jobs
                    begin
                      total_mb = mem_per_cpu * cpus.to_i
                      gb = (total_mb / 1024.0).round(1)
                      {
                        "display" => "#{gb} GB",
                        "mb" => total_mb
                      }
                    rescue
                      { "display" => "N/A", "mb" => nil }
                    end
                  else
                    { "display" => "N/A", "mb" => nil }
                  end

                  {
                    "id" => id,
                    "name" => name,
                    "user" => user,
                    "partition" => partition,
                    "state" => state,
                    "time" => time,
                    "time_limit" => time_limit,
                    "gpus" => gpu_count,
                    "cpus" => cpus.to_i,
                    "memory" => total_memory
                  }
                end
              end
            else
              Rails.logger.error "Failed to fetch jobs: #{jobs_output}"
              node_data["jobs"] = []
            end
            
            node_data
          else
            raise "Node not found"
          end
        else
          raise "Failed to fetch node status: #{output}"
        end
      end

      render json: node
    rescue StandardError => e
      status_code = e.message.include?("Node not found") ? :not_found : :internal_server_error
      render json: { error: e.message }, status: status_code
    end
  end
end 