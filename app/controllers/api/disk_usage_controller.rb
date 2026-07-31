require "open3"

module Api
  class DiskUsageController < ApplicationController
    # Columns the quota command is expected to emit, in order.
    COLUMNS = %i[
      type location disk_usage disk_usage_limit disk_usage_percentage
      file_count file_count_limit file_count_percentage
    ].freeze

    def get
      # No portable way to ask a cluster for quotas, so this is a site-local
      # command. Without one configured the widget has nothing to show; report
      # that as "no filesystems" rather than an error, so the page still renders.
      return render(json: [].to_json, status: :ok) unless ::Configuration.quota_command_enabled?

      quotas = Rails.cache.fetch(cache_key, expires_in: 60.seconds, race_condition_ttl: 3.seconds) do
        output, status = Open3.capture2(::Configuration.quota_command, @user.name)

        next nil unless status.success?

        parse(output)
      end

      if quotas
        render json: quotas.to_json, status: :ok
      else
        head :internal_server_error
      end
    end

    private

    # The command is site configuration, so a change to it must not keep serving
    # rows parsed from the previous one.
    def cache_key
      ["disk_usage", @user.name, ::Configuration.quota_command].join("/")
    end

    # Skips the command's header rows, then reads whitespace-separated columns.
    # Short rows are dropped rather than yielding entries full of nils.
    def parse(output)
      skip = ::Configuration.quota_command_skip_lines.to_i

      output.split("\n").drop(skip).filter_map do |line|
        fields = line.split
        next if fields.size < COLUMNS.size

        COLUMNS.zip(fields).to_h
      end
    end
  end
end
