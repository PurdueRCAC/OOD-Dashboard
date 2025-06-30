module Api
  class PartitionStatusController < ApplicationController
    EXCLUDED_PARTITIONS = ["cocosys", "gautschi-nodes", "profiling"].freeze

    def get
      partition_statuses = Rails.cache.fetch("partition_status", expires_in: 60.seconds, race_condition_ttl: 3.seconds) do
        # This script is the updated version of the showpartitions script found on Gautschi
        # The source is at https://github.com/OleHolmNielsen/Slurm_tools/blob/master/partitions/showpartitions
        partitions_output, partitions_status = Open3.capture2("sinfo -h -o '%R|%a|%F|%C'")
        gpus_output, gpus_status = Open3.capture2("scontrol show node --oneliner")
  
        if partitions_status == 0 && gpus_status == 0
          gpus_output_hash = Util.scontrol_to_hash(gpus_output)
          partitions_output.split("\n").map { |line|
            s = line.split("|")
            nodes = s[2].split("/")
            cores = s[3].split("/")
            gpus = gpus_output_hash.select { |node| node.key?("Partitions") && node["Partitions"].split(",").include?(s[0]) }.reduce([0, 0]) { |sum, line|
              alloctres_hash = line["AllocTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
              cfgtres_hash = line["CfgTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
              [sum[0] + (alloctres_hash["gres/gpu"] || 0).to_i, sum[1] + (cfgtres_hash["gres/gpu"] || 0).to_i]
            }
            { partition: s[0], state: s[1], total_nodes: nodes[3], allocated_nodes: nodes[0], other_nodes: nodes[2], free_nodes: nodes[1], total_cores: cores[3], allocated_cores: cores[0], other_cores: cores[2], free_cores: cores[1], allocated_gpus: gpus[0], total_gpus: gpus[1] }
          }.reject { |p| EXCLUDED_PARTITIONS.include?(p[:partition]) }
        else
          return false
        end
      end

      if partition_statuses
        render json: partition_statuses.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
