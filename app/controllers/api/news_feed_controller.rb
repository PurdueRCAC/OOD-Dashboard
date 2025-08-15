require "uri"
require "net/http"
require "json"

module Api
  class NewsFeedController < ApplicationController
    # 1: Outages and Maintenance
    # 2: Announcements
    # 3: Science Highlights
    # 6: Outages
    # 7: Maintenance
    NEWS_TYPE_IDS = [1, 2, 3, 6, 7]

    def get
      result = Rails.cache.fetch("news_feed", expires_in: 30.minutes, race_condition_ttl: 3.seconds) do
        uri = URI("https://www.rcac.purdue.edu/api/news?resource=113&limit=30")
        res = Net::HTTP.get_response(uri)

        if res.is_a?(Net::HTTPSuccess)
          json_data = JSON.parse(res.body)
          articles = json_data["data"]
          filtered = articles
            .select { |article| NEWS_TYPE_IDS.include?(article["newstypeid"].to_i) }
            .select { |article| article["resources"].any? { |resource| resource["name"] == "Gautschi" } }
          
          # Only keep the fields we need
          filtered.map do |article|
            {
              headline: article["headline"],
              uri: article["uri"],
              formatteddate: article["formatteddate"],
              formattedbody: article["formattedbody"],
              datetimenews: article["datetimenews"],
              datetimenewsend: article["datetimenewsend"],
              type: {
                id: article["newstypeid"].to_i
              },
              updates: (article["updates"] || []).map do |update|
                {
                  formattedbody: update["formattedbody"],
                  datetimecreated: update["datetimecreated"],
                  formattedcreateddate: update["formattedcreateddate"]
                }
              end
            }
          end
        else
          return false
        end
      end

      if result
        render json: result, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
