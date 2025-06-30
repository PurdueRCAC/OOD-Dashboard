require 'open3'

module Api
  class JobsController < ApplicationController
    FIELD_INFO = {
      # Timestamps
      "Submit" => { type: :timestamp, scontrol: "SubmitTime", sacct: "Submit" },
      "Start" => { type: :timestamp, scontrol: "StartTime", sacct: "Start" },
      "End" => { type: :timestamp, scontrol: "EndTime", sacct: "End" },
      "Eligible" => { type: :timestamp, scontrol: "EligibleTime", sacct: "Eligible" },
      "AccrueTime" => { type: :timestamp, scontrol: "AccrueTime" },
      "PreemptEligibleTime" => { type: :timestamp, scontrol: "PreemptEligibleTime" },
      "LastSchedEval" => { type: :timestamp, scontrol: "LastSchedEval" },
      "Deadline" => { type: :timestamp, scontrol: "Deadline" },
      "PreemptTime" => { type: :timestamp, scontrol: "PreemptTime" },

      # Durations
      "Elapsed" => { type: :duration, scontrol: "RunTime", sacct: "Elapsed", combinator: :time_max },
      "TotalCPU" => { type: :duration, sacct: "TotalCPU", combinator: :max },
      "UserCPU" => { type: :duration, sacct: "UserCPU", combinator: :max },
      "SystemCPU" => { type: :duration, sacct: "SystemCPU", combinator: :max },
      "Timelimit" => { type: :duration, scontrol: "TimeLimit", sacct: "Timelimit", combinator: :time_max },
      "Suspended" => { type: :duration, scontrol: "SuspendTime", sacct: "Suspended", combinator: :max },
      "MinCPU" => { type: :duration, sacct: "MinCPU", combinator: :min },
      "AveCPU" => { type: :duration, sacct: "AveCPU", combinator: :max },
      "CPUTime" => { type: :duration, sacct: "CPUTime", combinator: :max },
      "CPUTimeRAW" => { type: :integer, sacct: "CPUTimeRAW", combinator: :max },
      "PlannedCPU" => { type: :duration, sacct: "PlannedCPU", combinator: :min },
      "PlannedCPURAW" => { type: :integer, sacct: "PlannedCPURAW", combinator: :min },

      # Integers
      "AllocCPUS" => { type: :integer, sacct: "AllocCPUS", combinator: :max },
      "NCPUS" => { type: :integer, sacct: "NCPUS", scontrol: "NumCPUs", combinator: :max },
      "NNodes" => { type: :integer, sacct: "NNodes", scontrol: "NumNodes", combinator: :max },
      "NTasks" => { type: :integer, sacct: "NTasks", scontrol: "NumTasks", combinator: :max },
      "Priority" => { type: :integer, sacct: "Priority", scontrol: "Priority", combinator: :keep_first },
      "ReqCPUS" => { type: :integer, sacct: "ReqCPUS", combinator: :max },
      "UID" => { type: :integer, sacct: "UID", combinator: :keep_first },
      "GID" => { type: :integer, sacct: "GID", combinator: :keep_first },
      "ExitCode" => { type: :string, sacct: "ExitCode", scontrol: "ExitCode", combinator: :keep_first },
      "Nice" => { type: :integer, scontrol: "Nice" },
      "MinCPUsNode" => { type: :integer, scontrol: "MinCPUsNode" },
      "MinMemoryNode" => { type: :integer, scontrol: "MinMemoryNode" },
      "MinTmpDiskNode" => { type: :integer, scontrol: "MinTmpDiskNode" },
      "AllocNodes" => { type: :integer, sacct: "AllocNodes", combinator: :keep_first },
      "AssocID" => { type: :integer, sacct: "AssocID", combinator: :keep_first },
      "DBIndex" => { type: :integer, sacct: "DBIndex", combinator: :keep_first },
      "DerivedExitCode" => { type: :string, sacct: "DerivedExitCode", combinator: :keep_first },
      "ElapsedRaw" => { type: :integer, sacct: "ElapsedRaw", combinator: :max },
      "QOSRAW" => { type: :integer, sacct: "QOSRAW", combinator: :keep_first },
      "ReqNodes" => { type: :integer, sacct: "ReqNodes", combinator: :keep_first },
      "TimelimitRaw" => { type: :integer, sacct: "TimelimitRaw", combinator: :max },
      "WCKeyID" => { type: :integer, sacct: "WCKeyID", combinator: :keep_first },

      # Floats
      "AveCPUFreq" => { type: :float, sacct: "AveCPUFreq", combinator: :max },
      "AveDiskRead" => { type: :float, sacct: "AveDiskRead", combinator: :max },
      "AveDiskWrite" => { type: :float, sacct: "AveDiskWrite", combinator: :max },
      "AvePages" => { type: :float, sacct: "AvePages", combinator: :max },
      "AveRSS" => { type: :float, sacct: "AveRSS", combinator: :max },
      "AveVMSize" => { type: :float, sacct: "AveVMSize", combinator: :max },
      "ConsumedEnergy" => { type: :float, sacct: "ConsumedEnergy", combinator: :max },
      "ConsumedEnergyRaw" => { type: :float, sacct: "ConsumedEnergyRaw", combinator: :max },
      "MaxDiskRead" => { type: :float, sacct: "MaxDiskRead", combinator: :max },
      "MaxDiskWrite" => { type: :float, sacct: "MaxDiskWrite", combinator: :max },
      "MaxPages" => { type: :float, sacct: "MaxPages", combinator: :max },
      "MaxRSS" => { type: :float, sacct: "MaxRSS", combinator: :max },
      "MaxVMSize" => { type: :float, sacct: "MaxVMSize", combinator: :max },
      "ReqCPUFreq" => { type: :float, sacct: "ReqCPUFreq", combinator: :keep_first },
      "ReqCPUFreqMax" => { type: :float, sacct: "ReqCPUFreqMax", combinator: :keep_first },
      "ReqCPUFreqMin" => { type: :float, sacct: "ReqCPUFreqMin", combinator: :keep_first },
      "ReqCPUFreqGov" => { type: :float, sacct: "ReqCPUFreqGov", combinator: :keep_first },
      "Planned" => { type: :float, sacct: "Planned", combinator: :min },

      # Step-specific fields (set_union)
      "MaxDiskReadNode" => { type: :step_data, sacct: "MaxDiskReadNode", combinator: :set_union },
      "MaxDiskWriteNode" => { type: :step_data, sacct: "MaxDiskWriteNode", combinator: :set_union },
      "MaxPagesNode" => { type: :step_data, sacct: "MaxPagesNode", combinator: :set_union },
      "MaxRSSNode" => { type: :step_data, sacct: "MaxRSSNode", combinator: :set_union },
      "MaxVMSizeNode" => { type: :step_data, sacct: "MaxVMSizeNode", combinator: :set_union },
      "State" => { type: :step_data, sacct: "State", scontrol: "JobState", combinator: :set_union },
      "TRESUsageInMaxNode" => { type: :step_data, sacct: "TRESUsageInMaxNode", combinator: :set_union },
      "TRESUsageOutMaxNode" => { type: :step_data, sacct: "TRESUsageOutMaxNode", combinator: :set_union },

      # String fields
      "Account" => { type: :string, sacct: "Account", scontrol: "Account", combinator: :keep_first },
      "JobName" => { type: :string, sacct: "JobName", scontrol: "JobName", combinator: :keep_first },
      "User" => { type: :string, sacct: "User", scontrol: "UserId", combinator: :keep_first },
      "Group" => { type: :string, sacct: "Group", scontrol: "GroupId", combinator: :keep_first },
      "Partition" => { type: :string, sacct: "Partition", scontrol: "Partition", combinator: :keep_first },
      "QOS" => { type: :string, sacct: "QOS", scontrol: "QOS", combinator: :keep_first },
      "Reason" => { type: :string, sacct: "Reason", scontrol: "Reason", combinator: :keep_first },
      "WorkDir" => { type: :string, sacct: "WorkDir", scontrol: "WorkDir", combinator: :keep_first },
      "AdminComment" => { type: :string, sacct: "AdminComment", combinator: :keep_first },
      "AllocTRES" => { type: :string, sacct: "AllocTRES", scontrol: "AllocTRES", combinator: :keep_first },
      "BlockID" => { type: :string, sacct: "BlockID", combinator: :keep_first },
      "Cluster" => { type: :string, sacct: "Cluster", combinator: :keep_first },
      "Comment" => { type: :string, sacct: "Comment", combinator: :keep_first },
      "Constraints" => { type: :string, sacct: "Constraints", combinator: :keep_first },
      "Container" => { type: :string, sacct: "Container", combinator: :keep_first },
      "Extra" => { type: :string, sacct: "Extra", combinator: :keep_first },
      "FailedNode" => { type: :string, sacct: "FailedNode", combinator: :keep_first },
      "Flags" => { type: :string, sacct: "Flags", combinator: :keep_first },
      "JobID" => { type: :string, sacct: "JobID", scontrol: "JobId", combinator: :keep_first },
      "JobIDRaw" => { type: :string, sacct: "JobIDRaw", combinator: :keep_first },
      "Layout" => { type: :string, sacct: "Layout", combinator: :keep_first },
      "Licenses" => { type: :string, sacct: "Licenses", scontrol: "Licenses", combinator: :keep_first },
      "MaxDiskReadTask" => { type: :string, sacct: "MaxDiskReadTask", combinator: :keep_first },
      "MaxDiskWriteTask" => { type: :string, sacct: "MaxDiskWriteTask", combinator: :keep_first },
      "MaxPagesTask" => { type: :string, sacct: "MaxPagesTask", combinator: :keep_first },
      "MaxRSSTask" => { type: :string, sacct: "MaxRSSTask", combinator: :keep_first },
      "MaxVMSizeTask" => { type: :string, sacct: "MaxVMSizeTask", combinator: :keep_first },
      "McsLabel" => { type: :string, sacct: "McsLabel", scontrol: "MCS_label", combinator: :keep_first },
      "MinCPUNode" => { type: :string, sacct: "MinCPUNode", combinator: :keep_first },
      "MinCPUTask" => { type: :string, sacct: "MinCPUTask", combinator: :keep_first },
      "NodeList" => { type: :nodelist, sacct: "NodeList", scontrol: "NodeList", combinator: :keep_first },
      "ReqMem" => { type: :string, sacct: "ReqMem", combinator: :keep_first },
      "ReqTRES" => { type: :string, sacct: "ReqTRES", scontrol: "ReqTRES", combinator: :keep_first },
      "Reservation" => { type: :string, sacct: "Reservation", combinator: :keep_first },
      "ReservationId" => { type: :string, sacct: "ReservationId", combinator: :keep_first },
      "StdErr" => { type: :string, sacct: "StdErr", scontrol: "StdErr", combinator: :keep_first },
      "StdIn" => { type: :string, sacct: "StdIn", scontrol: "StdIn", combinator: :keep_first },
      "StdOut" => { type: :string, sacct: "StdOut", scontrol: "StdOut", combinator: :keep_first },
      "SubmitLine" => { type: :string, sacct: "SubmitLine", combinator: :keep_first },
      "SystemComment" => { type: :string, sacct: "SystemComment", combinator: :keep_first },
      "TRES" => { type: :string, sacct: "TRES", combinator: :keep_first },
      "TRESUsageInMaxTask" => { type: :string, sacct: "TRESUsageInMaxTask", combinator: :keep_first },
      "TRESUsageInMinNode" => { type: :string, sacct: "TRESUsageInMinNode", combinator: :keep_first },
      "TRESUsageInMinTask" => { type: :string, sacct: "TRESUsageInMinTask", combinator: :keep_first },
      "TRESUsageOutMaxTask" => { type: :string, sacct: "TRESUsageOutMaxTask", combinator: :keep_first },
      "TRESUsageOutMinNode" => { type: :string, sacct: "TRESUsageOutMinNode", combinator: :keep_first },
      "TRESUsageOutMinTask" => { type: :string, sacct: "TRESUsageOutMinTask", combinator: :keep_first },
      "WCKey" => { type: :string, sacct: "WCKey", combinator: :keep_first },

      # Scontrol-only string fields
      "Dependency" => { type: :string, scontrol: "Dependency" },
      "Requeue" => { type: :string, scontrol: "Requeue" },
      "Restarts" => { type: :string, scontrol: "Restarts" },
      "BatchFlag" => { type: :string, scontrol: "BatchFlag" },
      "Reboot" => { type: :string, scontrol: "Reboot" },
      "TimeMin" => { type: :string, scontrol: "TimeMin" },
      "SecsPreSuspend" => { type: :string, scontrol: "SecsPreSuspend" },
      "Scheduler" => { type: :string, scontrol: "Scheduler" },
      "AllocSid" => { type: :string, scontrol: "AllocNode:Sid" },
      "ReqNodeList" => { type: :string, scontrol: "ReqNodeList" },
      "ExcNodeList" => { type: :string, scontrol: "ExcNodeList" },
      "BatchHost" => { type: :string, scontrol: "BatchHost" },
      "CPUsPerTask" => { type: :string, scontrol: "CPUs/Task" },
      "ReqBSCT" => { type: :string, scontrol: "ReqB:S:C:T" },
      "SocksPerNode" => { type: :string, scontrol: "Socks/Node" },
      "NtasksPerNBSC" => { type: :string, scontrol: "NtasksPerN:B:S:C" },
      "CoreSpec" => { type: :string, scontrol: "CoreSpec" },
      "Features" => { type: :string, scontrol: "Features" },
      "DelayBoot" => { type: :string, scontrol: "DelayBoot" },
      "OverSubscribe" => { type: :string, scontrol: "OverSubscribe" },
      "Contiguous" => { type: :string, scontrol: "Contiguous" },
      "Network" => { type: :string, scontrol: "Network" },
      "Command" => { type: :string, scontrol: "Command" }
    }.freeze

    COMPUTED_FIELDS = {
      "memory_efficiency" => {
        type: :float,
        compute: ->(data) {
          if data["MaxRSS"] && data["ReqMem"]
            # Convert MaxRSS to bytes and ReqMem to bytes, then calculate ratio
            max_rss = data["MaxRSS"].to_f * 1024  # MaxRSS is in KB
            if data["ReqMem"] =~ /(\d+)([MGT])n?/
              value = $1.to_f
              unit = $2
              req_mem = case unit
                      when 'G' then value * 1024 * 1024 * 1024
                      when 'M' then value * 1024 * 1024
                      when 'T' then value * 1024 * 1024 * 1024 * 1024
                      end
              max_rss / req_mem
            end
          end
        }
      },
      "cpu_efficiency" => {
        type: :float,
        compute: ->(data) {
          if data["TotalCPU"] && data["Elapsed"] && data["AllocCPUS"]
            data["TotalCPU"] / (data["Elapsed"] * data["AllocCPUS"])
          end
        }
      },
      "time_efficiency" => {
        type: :float,
        compute: ->(data) {
          if data["Elapsed"] && data["Timelimit"]
            data["Elapsed"] / data["Timelimit"].to_f
          end
        }
      },
      "UsedGPUHours" => {
        type: :float,
        compute: ->(data) {
          if data["Partition"] && data["QOS"] && data["Elapsed"] && data["Timelimit"] && data["ReqTRES"]
            used_gpu_hours, _ = Util.get_gpu_hours_usage(
              data["JobID"],
              data["Partition"],
              data["QOS"],
              data["Elapsed"],
              data["Timelimit"],
              data["ReqTRES"]
            )
            used_gpu_hours
          end
        }
      },
      "TotalGPUHours" => {
        type: :float,
        compute: ->(data) {
          if data["Partition"] && data["QOS"] && data["Elapsed"] && data["Timelimit"] && data["ReqTRES"]
            _, total_su = Util.get_gpu_hours_usage(
              data["JobID"],
              data["Partition"],
              data["QOS"],
              data["Elapsed"],
              data["Timelimit"],
              data["ReqTRES"]
            )
            total_su
          end
        }
      },
      "SessionId" => {
        type: :string,
        compute: ->(data) {
          if data["JobID"]
            Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end&.id
          end
        }
      },
      "SessionPath" => {
        type: :string,
        compute: ->(data) {
          if data["JobID"]
            Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end&.staged_root&.to_s
          end
        }
      },
      "SessionAppName" => {
        type: :string,
        compute: ->(data) {
          if data["JobID"]
            Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end&.title
          end
        }
      },
      "SessionAppUrl" => {
        type: :string,
        compute: ->(data) {
          if data["JobID"]
            session = Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end
            if session&.app
              Rails.application.routes.url_helpers.new_batch_connect_session_context_path(token: session.app.token)
            end
          end
        }
      },
      "SessionConnection" => {
        type: :string,
        compute: ->(data) {
        if data["JobID"]
          session = Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end
            if session
              connection_html = ""
              if session.running?
                if session.view
                  connection_html += ApplicationController.renderer.render(
                    partial: "batch_connect/sessions/connections/custom",
                    locals: { view: session.view, connect: session.connect }
                  )
                  connection_html = "<div style='width: 100%; max-width: 700px;'>#{connection_html}</div>"
                else
                  if session.vnc?
                    views = []
                    views << { title: "noVNC Connection", content: ApplicationController.renderer.render(
                      partial: "batch_connect/sessions/connections/novnc",
                      locals: { connect: session.connect, app_title: session.title }
                    )}
                    if ENV["ENABLE_NATIVE_VNC"]
                      views << { title: "Native Instructions", content: ApplicationController.renderer.render(
                        partial: "batch_connect/sessions/connections/native_vnc",
                        locals: { connect: session.connect }
                      )}
                    end
                    
                    if views.size == 1
                      connection_html += views.first[:content]
                    else
                      tabs_html = "<ul class='nav nav-tabs'>"
                      views.each_with_index do |view, idx|
                        tabs_html += "<li class='nav-item #{'active' if idx.zero?}'>"
                        tabs_html += "<a href='#c_#{session.id}_#{idx}' data-toggle='tab' aria-selected='#{idx.zero?}' class='nav-link #{'active' if idx.zero?}'>#{view[:title]}</a>"
                        tabs_html += "</li>"
                      end
                      tabs_html += "</ul>"

                      content_html = "<div class='tab-content'>"
                      views.each_with_index do |view, idx|
                        content_html += "<div id='c_#{session.id}_#{idx}' class='tab-pane ood-appkit markdown #{'active' if idx.zero?}' role='tabpanel'>"
                        content_html += view[:content]
                        content_html += "</div>"
                      end
                      content_html += "</div>"

                      connection_html += "<div>#{tabs_html}#{content_html}</div>"
                    end

                    connection_html = "<div style='width: 100%; max-width: 700px;'>#{connection_html}</div>"
                  else
                    connection_html += ApplicationController.renderer.render(partial: "batch_connect/sessions/connections/missing_connection")
                  end
                end
              elsif session.starting?
                connection_html += ApplicationController.renderer.render(partial: "batch_connect/sessions/connections/starting")
              elsif session.queued?
                connection_html += ApplicationController.renderer.render(partial: "batch_connect/sessions/connections/queued")
                # elsif session.completed?
                #   connection_html += ApplicationController.renderer.render(
                #     partial: "batch_connect/sessions/connections/completed",
                #     locals: { session: session }
                #   )
                # else
                #   connection_html += ApplicationController.renderer.render(partial: "batch_connect/sessions/connections/bad")
              end
            end
          end
          connection_html
        }
      },
      "SessionConnectionInfo" => {
        type: :string,
        compute: ->(data) {
          if data["JobID"]
            session = Rails.cache.fetch("session_lookup/#{data["JobID"]}", expires_in: 1.second) do
              BatchConnect::Session.find_by_job_id(data["JobID"])
            end
            if session&.app&.session_info_view
              session.render_info_view
            end
          end
        }
      }
    }.freeze

    def show
      job_id = params[:jobid]
      
      # Add 1-second cache using Rails.cache
      job_data = Rails.cache.fetch("job_data/#{job_id}", expires_in: 1.second) do
        get_job_info(job_id)
      end

      if job_data.nil?
        return head :not_found
      end

      render json: job_data, status: :ok
    end

    def cancel
      job_id = params[:jobid]
      
      # Validate job ID format
      unless /^\d+(_\d+)?$/.match?(job_id)
        return render json: { error: "Invalid job ID format." }, status: :bad_request
      end

      # Get job info to check ownership
      job_data = get_job_info(job_id)
      
      if job_data.nil?
        return render json: { error: "Job #{job_id} not found." }, status: :not_found
      end

      # Extract username without parentheses for comparison
      job_username = job_data["User"].to_s.split('(').first.strip
      
      # Check if current user owns the job
      unless job_username == @user.name
        return render json: { error: "Permission denied: you can only cancel your own jobs." }, 
                     status: :forbidden
      end

      # Execute scancel command
      output, status = Open3.capture2e("scancel", job_id)
      
      if status.success?
        render json: { message: "Job #{job_id} cancelled successfully" }, status: :ok
      else
        Rails.logger.error("Failed to cancel job #{job_id}: #{output.strip}")
        render json: { error: "Failed to cancel job #{job_id}." }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("Failed to cancel job #{job_id}: #{e.message}")
      render json: { error: "Failed to cancel job #{job_id}." }, status: :internal_server_error
    end

    private

    def get_job_info(job_id)
      # Validate job ID format
      return nil if !(/^\d+(_\d+)?$/.match?(job_id))

      # Get all possible sacct fields from FIELD_INFO
      sacct_fields = FIELD_INFO.values.map { |info| info[:sacct] }.compact.join(',')

      base_job_id = job_id.split("_").first

      # Get detailed job info from scontrol and sacct
      scontrol_output, scontrol_status = Open3.capture2e("scontrol show job #{job_id} -d -o")
      sacct_output, sacct_status = Open3.capture2e("sacct -j #{base_job_id} -P -n --array --expand-patterns --format=#{sacct_fields}")

      # Check if either command succeeded
      return nil if scontrol_output.blank? && sacct_output.blank?

      # Pass the requested job_id to parse_sacct_output
      parse_job_info(scontrol_output, sacct_output, sacct_fields, job_id)
    end

    def parse_job_info(scontrol_output, sacct_output, sacct_fields, job_id)
      # Parse outputs
      scontrol_data = parse_scontrol_output(scontrol_output)
      sacct_data = parse_sacct_output(sacct_output, sacct_fields, job_id)

      # Merge data prioritizing scontrol
      merge_job_data(scontrol_data, sacct_data, sacct_output, sacct_fields)
    end

    def parse_scontrol_output(output)
      return {} if output.blank?

      begin
        output.split("\n").map { |line| 
          line.scan(/(?:(?<=\A|\s))([^\s=]+)=((?:(?!\s(?:\S+)=).)*)/).to_h.transform_values(&:strip)
        }.first || {}
      rescue => e
        Rails.logger.error("Error parsing scontrol output: #{e.message}")
        {}
      end
    end

    def parse_sacct_output(sacct_output, sacct_fields, requested_job_id)
      sacct_data = {}
      step_ids = Set.new
      
      # Initialize fields
      FIELD_INFO.each do |field, info|
        sacct_data[info[:sacct]] = info[:combinator] == :set_union ? {} : nil if info[:sacct]
      end

      if !sacct_output.blank?
        # First pass: collect step IDs that match the requested job ID
        sacct_output.split("\n").each do |line|
          fields = line.split("|")
          next if fields.empty?

          sacct_fields.split(",").each_with_index do |field, index|
            if field == "JobID"
              job_id = fields[index]
              # Split by dot to handle cases like "12345_3.batch"
              base_id = job_id&.split('.')&.first
              if base_id == requested_job_id
                step_ids.add(job_id)
              end
              break
            end
          end
        end

        # Second pass: process data only for matching job IDs
        sacct_output.split("\n").each do |line|
          fields = line.split("|")
          next if fields.empty?

          line_data = {}
          step_id = nil
          matches_requested_id = false

          sacct_fields.split(",").each_with_index do |field, index|
            value = fields[index]
            if field == "JobID"
              step_id = value
              # Split by dot to handle cases like "12345_3.batch"
              base_id = step_id&.split('.')&.first
              matches_requested_id = (base_id == requested_job_id)
              break unless matches_requested_id
            end
            
            # Handle state conversion for CANCELLED states
            if field == "State"
              value = convert_cancelled_state(value)
            end

            line_data[field] = convert_field_value(value)
          end

          next if step_id.nil? || !matches_requested_id

          # Update sacct_data based on combinators
          line_data.each do |field, value|
            next if value.nil?

            FIELD_INFO.each do |_, info|
              next unless info[:sacct] == field

              # Default to keep_first if no combinator specified
              combinator = info[:combinator] || :keep_first

              case combinator
              when :keep_first
                sacct_data[field] ||= value
              when :max
                if sacct_data[field].nil? || 
                   (parse_numeric(value) || -Float::INFINITY) > (parse_numeric(sacct_data[field]) || -Float::INFINITY)
                  sacct_data[field] = value
                end
              when :min
                if sacct_data[field].nil? || 
                   (parse_numeric(value) || Float::INFINITY) < (parse_numeric(sacct_data[field]) || Float::INFINITY)
                  sacct_data[field] = value
                end
              when :time_max
                if sacct_data[field].nil? || 
                   (timestr_to_seconds(value) || -Float::INFINITY) > (timestr_to_seconds(sacct_data[field]) || -Float::INFINITY)
                  sacct_data[field] = value
                end
              when :time_min
                if sacct_data[field].nil? || 
                   (timestr_to_seconds(value) || Float::INFINITY) < (timestr_to_seconds(sacct_data[field]) || Float::INFINITY)
                  sacct_data[field] = value
                end
              when :set_union
                sacct_data[field][step_id] = value
              end
            end
          end
        end

        # Ensure all set_union fields have entries for all step IDs
        FIELD_INFO.each do |_, info|
          if info[:combinator] == :set_union && info[:sacct]
            step_ids.each do |step_id|
              sacct_data[info[:sacct]][step_id] = nil unless sacct_data[info[:sacct]].key?(step_id)
            end
          end
        end
      end

      sacct_data
    end

    def collect_job_array_data(sacct_output, sacct_fields, requested_job_id)
      return [] if sacct_output.blank?

      job_array_data = []
      base_array_job = requested_job_id.include?('_') ? requested_job_id.split('_').first : requested_job_id
      
      sacct_output.split("\n").each do |line|
        fields = line.split("|")
        next if fields.empty?

        job_id_index = sacct_fields.split(",").index("JobID")
        job_id = fields[job_id_index]
        
        # Only process main job entries (no .batch, .extern, etc)
        next if !job_id || job_id.include?('.')
        
        # Only include jobs that are part of this array
        next unless job_id.split("_").first == base_array_job
        # Skip the parent job ID if we're looking at a task
        next if requested_job_id.include?('_') && job_id == base_array_job

        # Collect relevant fields for the job array listing
        array_entry = {}
        sacct_fields.split(",").each_with_index do |field, index|
          value = fields[index]
          case field
          when "JobID"
            array_entry[field] = convert_field_value(value)
          when "State"
            array_entry[field] = convert_cancelled_state(value)
          when "Submit", "Start", "End"
            array_entry[field] = timestamp_to_epoch(value)
          when "Elapsed"
            array_entry[field] = timestr_to_seconds(value)
          when "ExitCode"
            array_entry[field] = convert_field_value(value)
          when "NodeList"
            array_entry[field] = expand_nodelist(convert_field_value(value))
          end
        end
        
        job_array_data << array_entry unless array_entry.empty?
      end

      job_array_data
    end

    def convert_cancelled_state(value)
      if value =~ /^CANCELLED by (\d+)$/
        username = Rails.cache.fetch("user_id/#{$1}") do
          `id -un #{$1}`.strip
        end
        value = "CANCELLED by #{username}" if $?.success?
      end
      value
    end

    def convert_field_value(value)
      if value.nil? || value.empty? || value == "Unknown" || value == "null"
        nil
      else
        value
      end
    end

    def merge_job_data(scontrol_data, sacct_data, sacct_output, sacct_fields)
      merged_data = {}
      
      # Process regular fields
      FIELD_INFO.keys.sort.each do |field|
        info = FIELD_INFO[field]

        value = if info[:scontrol] && scontrol_data[info[:scontrol]].present?
          convert_value(scontrol_data[info[:scontrol]], info[:type])
        elsif info[:sacct] && sacct_data[info[:sacct]].present?
          convert_value(sacct_data[info[:sacct]], info[:type])
        end

        merged_data[field] = value
      end

      # Process computed fields
      COMPUTED_FIELDS.keys.sort.each do |field|
        info = COMPUTED_FIELDS[field]
        begin
          merged_data[field] = info[:compute].call(merged_data)
        rescue => e
          Rails.logger.error("Error computing field #{field}: #{e.message}")
          merged_data[field] = nil
        end
      end

      # Add JobArray field if any job IDs contain underscore
      job_id = merged_data["JobID"]
      if job_id && has_array_tasks?(sacct_output, sacct_fields)
        merged_data["JobArray"] = collect_job_array_data(sacct_output, sacct_fields, job_id)
      else
        merged_data["JobArray"] = []
      end

      # Change PENDING to REQUEUED if there are restarts
      if merged_data["Restarts"] && merged_data["Restarts"]&.to_i > 0
        merged_data["State"] = "REQUEUED"
      end

      merged_data
    end

    def has_array_tasks?(sacct_output, sacct_fields)
      return false if sacct_output.blank?

      job_id_index = sacct_fields.split(",").index("JobID")
      return false unless job_id_index

      sacct_output.split("\n").any? do |line|
        fields = line.split("|")
        next if fields.empty?
        
        job_id = fields[job_id_index]
        job_id&.include?('_')
      end
    end

    def convert_value(value, type)
      return nil if value.nil? || value == "N/A" || value == "(null)" || value == "None" || value == "Unknown"

      case type
      when :timestamp
        ts = timestamp_to_epoch(value)
        ts == "N/A" ? nil : ts
      when :duration
        seconds = timestr_to_seconds(value).to_f
        seconds < 0 ? nil : seconds
      when :integer
        return nil if value == "-1" || !value.to_i.to_s == value
        value.to_i
      when :float
        return nil if !value.to_f.to_s == value
        value.to_f
      when :nodelist
        expand_nodelist(value)
      when :step_data, :string
        value
      end
    end

    def parse_numeric(value)
      return nil if value.nil?
      if value =~ /^\d+$/
        value.to_i
      elsif value =~ /^\d*\.\d+$/
        value.to_f
      else
        nil
      end
    end

    def timestamp_to_epoch(timestamp)
      begin
        Time.strptime(timestamp, "%FT%T").to_i
      rescue ArgumentError => e
        "N/A"
      end
    end

    def timestr_to_seconds(timestr)
      d_hhmmss_regex = /\A\d+-\d{2}:\d{2}:\d{2}\z/
      hhmmss_regex = /\A\d{2}:\d{2}:\d{2}\z/
      mmss_ms_regex = /\A\d{2}:\d{2}\.\d{3}\z/

      if d_hhmmss_regex.match?(timestr)
        parts = timestr.split("-")
        days = parts.first.to_i
        hours, minutes, seconds = parts.last.split(":").map(&:to_i)
        total_seconds = days * 86400 + hours * 3600 + minutes * 60 + seconds
      elsif hhmmss_regex.match?(timestr)
        hours, minutes, seconds = timestr.split(":").map(&:to_i)
        total_seconds = hours * 3600 + minutes * 60 + seconds
      elsif mmss_ms_regex.match?(timestr)
        minutes, seconds_milliseconds = timestr.split(":")
        seconds, milliseconds = seconds_milliseconds.split(".")
        total_seconds = ((minutes.to_i * 60) + seconds.to_i + (milliseconds.to_i / 1000.0)).round
      else
        return -1
      end

      total_seconds
    end

    def expand_nodelist(value)
      return nil if value.nil? || value == "(null)" || value == "None" || value == "N/A"

      nodes = []
      if match = value.match(/^([a-zA-Z]+)\[([\d\-,]+)\]$/)
        prefix = match[1]
        ranges = match[2].split(',')
        
        ranges.each do |range|
          if range.include?('-')
            start, finish = range.split('-').map(&:to_i)
            (start..finish).each { |n| nodes << "#{prefix}#{n}" }
          else
            nodes << "#{prefix}#{range}"
          end
        end
      else
        nodes = value.split(',')
      end

      nodes
    end
  end
end 