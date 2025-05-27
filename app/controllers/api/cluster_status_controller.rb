module Api
  class ClusterStatusController < ApplicationController
    def get
      nodes = Rails.cache.fetch("cluster_status", expires_in: 30.seconds, race_condition_ttl: 3.seconds) do
        output, status = Open3.capture2("scontrol show node -a --oneliner")
        
        unless status.success?
          raise "Failed to fetch cluster status"
        end
        
        nodes_hash = Util.scontrol_to_hash(output)
        
        nodes_hash.filter_map do |node|
          next unless node["NodeName"]&.match?(/\A[abghi]\d+\z/)
          
          alloctres_hash = node["AllocTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
          cfgtres_hash = node["CfgTRES"].split(',').map { |pair| pair.split('=', 2) }.to_h
          {
            "NodeName" => node["NodeName"],
            "State" => node["State"],
            "Partitions" => node["Partitions"]&.split(",") || [],
            "CPUAlloc" => node["CPUAlloc"],
            "CPUTot" => node["CPUTot"],
            "CPULoad" => node["CPULoad"],
            "RealMemory" => node["RealMemory"],
            "AllocMem" => node["AllocMem"],
            "FreeMem" => node["FreeMem"],
            "GPUTot" => (cfgtres_hash["gres/gpu"] || 0).to_i,
            "GPULoad" => (alloctres_hash["gres/gpu"] || 0).to_i
          }
        end
      end

      render json: nodes
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end 