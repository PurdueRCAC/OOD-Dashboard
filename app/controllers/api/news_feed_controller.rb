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

      # skip_nil so an unreachable endpoint is not cached for half an hour: the
      # block yields nil on failure and the next request retries.
      result = Rails.cache.fetch(cache_key, expires_in: 30.minutes, race_condition_ttl: 3.seconds, skip_nil: true) do
        body = fetch_feed(::Configuration.news_feed_url)

        if body
          # A misconfigured endpoint can return an HTML error page or a captive
          # portal instead of JSON; that is a widget that hides itself, not a
          # 500 for the whole dashboard.
          json_data = begin
            JSON.parse(body)
          rescue JSON::ParserError => e
            Rails.logger.warn("News feed at #{::Configuration.news_feed_url.inspect} returned unparsable JSON: #{e.message}")
            nil
          end
          next nil if json_data.nil?

          articles = json_data["data"]
          filtered = articles
            .select { |article| NEWS_TYPE_IDS.include?(article["newstypeid"].to_i) }
            .select { |article| matches_resource_filter?(article) }

          # Only keep the fields we need. The feed is remote HTML from a
          # site-configured endpoint, and the widget renders it as markup, so
          # sanitize the bodies and allow-list the link scheme here rather than
          # trusting whatever the endpoint returns.
          filtered.map do |article|
            {
              headline: article["headline"],
              uri: safe_uri(article["uri"]),
              formatteddate: article["formatteddate"],
              formattedbody: sanitize_body(article["formattedbody"]),
              datetimenews: article["datetimenews"],
              datetimenewsend: article["datetimenewsend"],
              type: {
                id: article["newstypeid"].to_i
              },
              updates: (article["updates"] || []).map do |update|
                {
                  formattedbody: sanitize_body(update["formattedbody"]),
                  datetimecreated: update["datetimecreated"],
                  formattedcreateddate: update["formattedcreateddate"]
                }
              end
            }
          end
        else
          # `next`, not `return`: `return` here returned from the whole action,
          # so the :internal_server_error below was unreachable and Rails
          # replied 204 instead.
          next nil
        end
      end

      if result
        render json: result, status: :ok
      else
        head :internal_server_error
      end
    end

    private

    # Tags and attributes the widget needs to render an article body. Anything
    # else -- <script>, <iframe>, event handlers, style -- is stripped.
    ALLOWED_TAGS = %w[p br strong b em i u ul ol li a h1 h2 h3 h4 h5 h6 blockquote code pre span div table thead tbody tr th td].freeze
    ALLOWED_ATTRIBUTES = %w[href title].freeze

    # Schemes a feed link may use. Notably excludes `javascript:`, which would
    # otherwise execute when the widget puts the value in an href.
    ALLOWED_URI_SCHEMES = %w[http https].freeze

    # @return [String, nil] the article body with unsafe markup removed
    def sanitize_body(html)
      return nil if html.nil?

      ActionController::Base.helpers.sanitize(
        html.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
      )
    end

    # @return [String, nil] the link if it is http(s), otherwise nil so the
    #   widget renders the headline without one
    def safe_uri(uri)
      return nil if uri.blank?

      parsed = URI.parse(uri.to_s)
      ALLOWED_URI_SCHEMES.include?(parsed.scheme&.downcase) ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    # The feed source may be an HTTP(S) endpoint or a local JSON file, the same
    # way OOD's quota and balance paths accept either. Returns the raw body, or
    # nil if it could not be read.
    def fetch_feed(source)
      if source.to_s.start_with?('http://', 'https://')
        # Bounded: a hung endpoint would otherwise tie up a PUN thread until
        # the request times out at the web-server layer.
        res = Net::HTTP.start(
          URI(source).host, URI(source).port,
          use_ssl: URI(source).scheme == "https",
          open_timeout: 5, read_timeout: 10
        ) { |http| http.request(Net::HTTP::Get.new(URI(source))) }
        res.is_a?(Net::HTTPSuccess) ? res.body : nil
      elsif File.readable?(source.to_s)
        File.read(source.to_s)
      end
    rescue StandardError => e
      Rails.logger.warn("News feed fetch failed for #{source.inspect}: #{e.message}")
      nil
    end

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
