module Api
  class PartitionStatusController < ApplicationController
    def get
      excluded = ::Configuration.excluded_partitions

      # skip_nil so a scheduler failure is not cached: the block yields nil on
      # failure and the next request retries.
      partition_statuses = Rails.cache.fetch(["partition_status", excluded].join("/"), expires_in: 60.seconds, race_condition_ttl: 3.seconds, skip_nil: true) do
        # Derived from the showpartitions script
        # The source is at https://github.com/OleHolmNielsen/Slurm_tools/blob/master/partitions/showpartitions
        partitions_output, partitions_status = Open3.capture2("sinfo", "-h", "-o", "%R|%a|%F|%C")
        gpus_output, gpus_status = Open3.capture2("scontrol", "show", "node", "--oneliner")

        # `.success?`, not `== 0`: these are Process::Status, not integers, and
        # every sibling controller uses `.success?`.
        if partitions_status.success? && gpus_status.success?
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
          }.reject { |p| excluded.include?(p[:partition]) }
        else
          # `next`, not `return`: `return` here returned from the whole action,
          # so the :internal_server_error below was unreachable and Rails
          # replied 204 instead.
          next nil
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
