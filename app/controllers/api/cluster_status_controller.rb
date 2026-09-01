require "open3"

module Api
  class ClusterStatusController < ApplicationController
    def get
      # The filter participates in the key so that changing it takes effect on
      # the next request rather than after the cache expires.
      cache_key = ["cluster_status", ::Configuration.node_name_pattern].join("/")
      nodes = Rails.cache.fetch(cache_key, expires_in: 30.seconds, race_condition_ttl: 3.seconds) do
        output, status = Open3.capture2("scontrol", "show", "node", "-a", "--oneliner")

        unless status.success?
          raise "Failed to fetch cluster status"
        end
        
        nodes_hash = Util.scontrol_to_hash(output)

        # Which nodes to show is site configuration. Unset means show every
        # node the scheduler reports, so a site whose naming this fork has not
        # seen gets a populated page rather than a silently empty one.
        name_filter = ::Configuration.node_name_regexp

        selected = nodes_hash.filter_map do |node|
          next if node["NodeName"].blank?
          next if name_filter && !name_filter.match?(node["NodeName"])

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

        # The old hardcoded pattern emptied this page at any site whose nodes
        # are not named a/b/g/h/i + digits, and logged nothing -- the review
        # called it out as harder to diagnose than a crash. Say so instead.
        if selected.empty? && nodes_hash.any?
          Rails.logger.warn(
            "Cluster Status: OOD_NODE_NAME_PATTERN #{::Configuration.node_name_pattern.inspect} " \
            "matched none of the #{nodes_hash.size} nodes scontrol reported; the page will be empty"
          )
        end

        selected
      end

      render json: nodes
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end 