require "open3"

module Api
  class BalanceUsageController < ApplicationController
    def get
      user = @user.name

      allocations = Util.get_user_allocations(user)
      # The TRES config participates in the key so that changing it takes effect
      # immediately rather than after the hour-long cache expires.
      cache_key = ["balance_usage", user, ::Configuration.gpu_account_pattern,
                   ::Configuration.gpu_account_tres, ::Configuration.cpu_account_tres].join("/")
      mybalance = Rails.cache.fetch(cache_key, expires_in: 1.hours, race_condition_ttl: 3.seconds, skip_nil: true) do
        # No shell: `| tail -n +3` skipped the two header lines, which
        # `lines.drop(2)` does directly.
        raw_output, scontrol_status = Open3.capture2e(
          "scontrol", "show", "assoc", "users=#{user}", "accounts=#{allocations}", "flags=assoc", "-o"
        )
        output = raw_output.lines.drop(2).join

        if scontrol_status.success?
          parsed_data = Util.scontrol_to_hash(output)
          parsed_data.select { |line_h| line_h["UserName"].blank? }.filter_map { |line_h|
            account = line_h["Account"]
            tres_key = ::Configuration.account_tres_for(account)
            limit, used = Util.tres_pair(Util.tres_hash(line_h["GrpTRESMins"]), tres_key)

            # A site whose scheduler does not report this TRES gets a row-less
            # widget rather than an exception. Previously an unmatched line
            # became a nil that then blew up in sort_by.
            next if used.nil?

            # Get user's specific usage for this account
            user_line = parsed_data.find { |l|
              l["UserName"]&.match?(/\A#{Regexp.escape(user.to_s)}(\(\d+\))?\z/) &&
              l["Account"] == account
            }
            _user_limit, user_used = Util.tres_pair(Util.tres_hash(user_line&.[]("GrpTRESMins")), tres_key)

            {
              account: account,
              used: Util.tres_minutes_to_hours(used),
              user_used: Util.tres_minutes_to_hours(user_used),
              limit: limit.to_f.positive? ? Util.tres_minutes_to_hours(limit) : "No limit"
            }
          }.sort_by { |hash| hash[:account] }
        else
          # `next`, not `return`: `return` here returned from the whole action,
          # so the :internal_server_error below was unreachable and Rails
          # replied 204 instead.
          next nil
        end
      end

      if mybalance
        render json: mybalance.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
