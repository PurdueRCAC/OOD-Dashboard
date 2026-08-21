require "open3"

module Api
  class AccountListController < ApplicationController
    def get
      user = @user.name

      allocations = Util.get_user_allocations(user)
      myaccounts = Rails.cache.fetch("account_list/#{user}", expires_in: 1.minutes, race_condition_ttl: 3.seconds, skip_nil: true) do
        # No shell: `| tail -n +3` skipped the two header lines and
        # `| awk '{$1=$1}1'` collapsed the padding `%.60a` adds, both of which
        # are done in Ruby below.
        scontrol_raw, scontrol_status = Open3.capture2(
          "scontrol", "show", "assoc", "users=#{user}", "accounts=#{allocations}", "flags=assoc", "-o"
        )
        scontrol_output = scontrol_raw.lines.drop(2).join

        squeue_raw, squeue_status = Open3.capture2(
          "squeue", "-h", "--array", "-A", allocations.to_s,
          "-t", "PENDING,REQUEUED", "-a", "-r", "-o", "%.60a|%C"
        )
        squeue_output = squeue_raw.lines.map { |line| line.split.join(" ") }.join("\n")

        if scontrol_status.success? && squeue_status.success?
          cpu_queued_sums = squeue_output.scan(/(.+?)\|(\d+)/).each_with_object(Hash.new(0)) do |(account, cpus), h|
            h[account] += cpus.to_i
          end

          capacity_tres = ::Configuration.cpu_capacity_tres

          parsed_data = Util.scontrol_to_hash(scontrol_output)
          parsed_data.select { |line_h| line_h["UserName"].blank? }.map { |line_h|
            account = line_h["Account"]
            grp_tres = Util.tres_hash(line_h["GrpTRES"])
            grp_tres_mins = Util.tres_hash(line_h["GrpTRESMins"])

            # Which TRES holds the balance depends on the account. The sibling
            # balance_summary controller has always resolved it this way; this
            # one hardcoded "billing", which is why the two widgets could
            # disagree about the same allocation.
            balance_tres = ::Configuration.account_tres_for(account)

            cpu_limit, cpu_used = Util.tres_pair(grp_tres, capacity_tres)
            balance_limit, balance_used = Util.tres_pair(grp_tres_mins, balance_tres)

            user_line = parsed_data.find { |l|
              l["UserName"]&.match?(/\A#{Regexp.escape(user.to_s)}(\(\d+\))?\z/) &&
              l["Account"] == account
            }
            _user_limit, user_balance_used =
              Util.tres_pair(Util.tres_hash(user_line&.[]("GrpTRESMins")), balance_tres)

            {
              account: account,
              cpu_total: cpu_limit.to_i,
              cpu_queue: cpu_queued_sums[account],
              cpu_running: cpu_used.to_i,
              # Named for the balance, not for GPUs: what the billing TRES
              # denominates is site-specific (see balance_unit_label).
              balance_used: Util.tres_minutes_to_hours(balance_used),
              user_balance_used: Util.tres_minutes_to_hours(user_balance_used),
              balance_total: Util.tres_minutes_to_hours(balance_limit)
            }
          }.sort_by { |hash| hash[:account] }
        else
          # `next`, not `return`: `return` here returned from the whole action,
          # so the :internal_server_error below was unreachable and Rails
          # replied 204 instead.
          next nil
        end
      end

      if myaccounts
        render json: myaccounts.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
