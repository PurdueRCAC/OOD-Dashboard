require "open3"

module Api
  class BalanceSummaryController < ApplicationController
    def get
      allocation = params[:allocation]
      allocations = Util.get_user_allocations(@user.name)

      # Render directly: `return :not_in_allocation` returned the symbol from
      # this action, so nothing was rendered and Rails replied 204.
      if !(allocations && allocations.split(",").include?(allocation))
        return head :forbidden
      end

      balance_summary = Util.account_balance_rows(allocation)

      if balance_summary
        render json: balance_summary.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
