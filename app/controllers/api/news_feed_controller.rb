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
      return head :not_found unless ::Configuration.news_feed_enabled?

      result = Rails.cache.fetch(cache_key, expires_in: 30.minutes, race_condition_ttl: 3.seconds) do
        uri = URI(::Configuration.news_feed_url)
        res = Net::HTTP.get_response(uri)

        if res.is_a?(Net::HTTPSuccess)
          json_data = JSON.parse(res.body)
          articles = json_data["data"]
          filtered = articles
            .select { |article| NEWS_TYPE_IDS.include?(article["newstypeid"].to_i) }
            .select { |article| matches_resource_filter?(article) }

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

    private

    # The feed URL and filter are site configuration, so include them in the
    # cache key -- otherwise a config change keeps serving the old site's feed
    # until the entry expires.
    def cache_key
      ["news_feed", ::Configuration.news_feed_url, ::Configuration.news_feed_resource_filter].join("/")
    end

    # Sites whose news API covers several clusters can narrow the feed to one
    # of them by name. With no filter configured, every article is kept.
    def matches_resource_filter?(article)
      filter = ::Configuration.news_feed_resource_filter
      return true if filter.blank?

      Array(article["resources"]).any? { |resource| resource["name"] == filter }
    end
  end
end
