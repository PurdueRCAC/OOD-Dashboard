require "open3"

module Api
  # Same data as BalanceSummaryController, kept as a separate endpoint because
  # a separate widget calls it. Both delegate to one implementation so the two
  # cannot report different numbers for the same allocation.
  class GpuHourSummaryController < ApplicationController
    def get
      allocation = params[:allocation]
      allocations = Util.get_user_allocations(@user.name)

      # Render directly: `return :not_in_allocation` returned the symbol from
      # this action, so nothing was rendered and Rails replied 204.
      if !(allocations && allocations.split(",").include?(allocation))
        return head :forbidden
      end

      gpu_hour_summary = Util.account_balance_rows(allocation)

      if gpu_hour_summary
        render json: gpu_hour_summary.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
