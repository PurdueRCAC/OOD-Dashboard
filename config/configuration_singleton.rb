require 'pathname'
require 'dotenv'

# Dashboard app specific configuration singleton definition
# following the first proposal in:
#
# https://8thlight.com/blog/josh-cheek/2012/10/20/implementing-and-testing-the-singleton-pattern-in-ruby.html
#
# to avoid the traditional singleton approach or using class methods, both of
# which make it difficult to write tests against
#
# instead, ConfigurationSingleton is the definition of the configuration
# then the singleton instance used is a new class called "Configuration" which
# we set in config/boot i.e.
#
# Configuration = ConfigurationSingleton.new
#
# This is functionally equivalent to taking every instance method on
# ConfigurationSingleton and defining it as a class method on Configuration.
#
class ConfigurationSingleton
  attr_writer :app_development_enabled
  attr_writer :app_sharing_enabled

  # FIXME: temporary
  attr_accessor :app_sharing_facls_enabled
  alias_method :app_sharing_facls_enabled?, :app_sharing_facls_enabled

  def initialize
    add_boolean_configs
    add_string_configs
  end

  # All the boolean configurations that can be read through
  # environment variables or through the config file.
  #
  # @return [Hash] key/value pairs of defaults
  def boolean_configs
    {
      :csp_enabled                  => false,
      :csp_report_only              => false,
      :bc_dynamic_js                => false,
      :bc_simple_auto_accounts      => false,
      :bc_clean_old_dirs            => false,
      :bc_saved_settings            => false,
      :per_cluster_dataroot         => false,
      :remote_files_enabled         => false,
      :remote_files_validation      => false,
      :host_based_profiles          => false,
      :disable_bc_shell             => false,
      :cancel_session_enabled       => false,
      :hide_app_version             => false,
      :motd_render_html             => false,
      :upload_enabled               => true,
      :download_enabled             => true,
      # Serve invented cluster data instead of talking to a scheduler.
      # See config/initializers/demo_mode.rb.
      :demo_mode                    => false,
    }.freeze
  end

  # All the string configurations that can be read through
  # environment variables or through the config file.
  #
  # @return [Hash] key/value pairs of defaults
  def string_configs
    {
      :module_file_dir          => nil,
      :user_settings_file       => Pathname.new("~/.config/ondemand/settings.yml").expand_path.to_s,
      :facl_domain              => nil,
      :auto_groups_filter       => nil,
      :bc_clean_old_dirs_days   => '30',
      :google_analytics_tag_id  => nil,
      :project_template_dir     => "#{config_root}/projects",
      :rclone_extra_config      => nil,
      :default_profile          => nil,
      :project_size_timeout     => '15'
    }.merge(site_string_configs).freeze
  end

  # Site-specific string configurations.
  #
  # Every value below is a deployment detail that differs between sites (cluster
  # naming, documentation deep links, news feed endpoints, local filesystem
  # layout, local accounting rules). They are read exactly like the other
  # string configs -- from `OOD_<KEY>` in the environment, or from the key in
  # `/etc/ood/config/apps/dashboard/*.yml` -- so a site can configure the whole
  # dashboard without patching views.
  #
  # `nil` is the "not configured" value throughout: features that need a value
  # they do not have degrade gracefully (a doc link falls back to the general
  # docs URL, the news feed widget hides itself, GPU accounting reports "N/A").
  #
  # Three further site configs are read the same way but are not listed here,
  # because they need post-processing and so are defined as real methods below:
  # `site_name` (falls back to the dashboard title), `excluded_partitions` and
  # `gpu_hours_partitions` (both comma-separated lists).
  #
  # A key listed here must NOT also be defined as a method below.
  # `add_string_configs` defines singleton methods in the constructor, and those
  # take precedence over anything declared in the class body -- so a `def` with
  # the same name is silently ignored and callers get the raw string. Give the
  # derived form a different name (`node_name_pattern` here, read by
  # `node_name_regexp`), or keep the key out of this hash entirely.
  #
  # @return [Hash] key/value pairs of defaults
  def site_string_configs
    {
      # Optional logo shown next to the site name in the sidebar brand.
      :site_logo_url                      => nil,

      # Documentation deep links. Each falls back to OOD_DASHBOARD_DOCS_URL.
      :docs_accounts_url                  => nil,
      :docs_partitions_url                => nil,
      :docs_storage_url                   => nil,
      :docs_nodes_url                     => nil,

      # News feed widget. Expects a JSON endpoint shaped like the RCAC news
      # API (see app/controllers/api/news_feed_controller.rb). Leave unset to
      # hide the widget entirely.
      :news_feed_url                      => nil,
      # Optional resource name used to filter the feed to this cluster.
      :news_feed_resource_filter          => nil,
      # Human-facing news archive page linked from the widget header.
      :news_page_url                      => nil,

      # Scratch directory offered as a shortcut in the disk usage widget.
      # `$USER` is expanded to the current user's name.
      :scratch_dir_template               => nil,

      # Home directory the disk usage widget links into. Leave unset and it
      # uses the PUN process's own `$HOME`, which is correct wherever home
      # directories are per-user; set it only where the path the Files app
      # needs differs from `$HOME`. `$USER` is expanded.
      :home_dir_template                  => nil,

      # GPU model shown on node pages, mapping the GRES token the scheduler
      # reports to a human-readable name. A token with no mapping is displayed
      # as-is rather than left blank, so an unconfigured site still shows
      # something truthful.
      :gpu_models                         => 'l40:Nvidia L40,h100:Nvidia H100,h200:Nvidia H200',

      # Command the Storage widget runs to report filesystem quotas, given the
      # username as its only argument. There is no portable way to ask a cluster
      # this, so it is a site-local wrapper; leave unset and the widget hides
      # itself. Its output must be whitespace-separated columns:
      #   type location disk_used disk_limit disk_pct files file_limit file_pct
      # See demo/bin/myquota for a worked example.
      :quota_command                      => nil,
      # Header lines to skip before the first data row.
      :quota_command_skip_lines           => '3',

      # Slurm associations record an allocation's balance under a TRES name, and
      # which name depends on what the allocation is denominated in. Accounts
      # whose name matches `gpu_account_pattern` are read from
      # `gpu_account_tres`; every other account from `cpu_account_tres`.
      # Unset the pattern (the default) and every account is treated as CPU.
      :gpu_account_pattern                => nil,
      :gpu_account_tres                   => 'gres/gpu',
      :cpu_account_tres                   => 'cpu',

      # TRES the Accounts widget reads an allocation's CPU *capacity* from
      # (GrpTRES) -- a different axis from the balance (GrpTRESMins) above.
      # Standard Slurm reports capacity as `cpu`; sites metering a derived
      # resource set their own, e.g. `gres/hp_cpu`.
      :cpu_capacity_tres                  => 'cpu',

      # What an allocation's balance is denominated in, for display only. The
      # Accounts widget labels the figure with this, so a site whose billing
      # TRES is not GPU time can say "SUs" or "core-hours" instead.
      :balance_unit_label                 => 'GPU hours',

      # GPU-hour accounting. Sites that do not charge for GPU hours can leave
      # these unset, in which case GPU hours are reported as "N/A".
      # Jobs numbered at or below this id predate GPU accounting and are exempt.
      :gpu_hours_min_job_id               => nil,
      # QoS that is charged at a reduced rate, and that rate.
      :gpu_hours_discounted_qos           => nil,
      :gpu_hours_discounted_charge_factor => '0.25',

      # jobstats integration. Both must be set for per-job utilization metrics
      # to appear; see docs/CONFIGURATION.md for why an explicit interpreter is
      # needed.
      :jobstats_python                    => nil,
      :jobstats_script                    => nil,

      # Which nodes the Cluster Status page lists, as a regular expression
      # matched against the node name -- e.g. `\A(cn|gpu)-\d+\z`.
      #
      # Unset (the default) means show every node the scheduler reports. That
      # is the safe default for a site this fork has never seen: showing too
      # many nodes is visible and fixable, whereas the previous hardcoded
      # pattern showed *none* and said nothing about why.
      :node_name_pattern                  => nil
    }
  end

  # Read a site config that needs post-processing, rather than being surfaced
  # verbatim by `add_string_configs`. Same precedence as the generated
  # accessors: environment variable first, then the external config file.
  #
  # @return [String, nil] raw configured value
  def site_config(key)
    value = ENV["OOD_#{key.to_s.upcase}"]
    value.nil? ? config[key] : value
  end

  # Comma-separated site config parsed into a list of trimmed, non-empty values.
  #
  # @return [Array<String>]
  def site_config_list(key)
    site_config(key).to_s.split(',').map(&:strip).reject(&:empty?)
  end

  # @return [String] site display name, falling back to the dashboard title
  def site_name
    site_config(:site_name).presence || OodAppkit.dashboard.title
  end

  # @return [Array<String>] partitions to hide from the partition status widget
  def excluded_partitions
    site_config_list(:excluded_partitions)
  end

  # @return [Array<String>] partitions charged for GPU hours; empty means none
  def gpu_hours_partitions
    site_config_list(:gpu_hours_partitions)
  end

  # Partitions the Partition Status widget presents as GPU partitions, where
  # usage is drawn per GPU rather than per core.
  #
  # @return [Array<String>] empty means no partition is treated as GPU
  def gpu_partitions
    site_config_list(:gpu_partitions)
  end

  # Partitions allocated whole-node, where per-core usage is not meaningful.
  #
  # @return [Array<String>] empty means none
  def wholenode_partitions
    site_config_list(:wholenode_partitions)
  end

  # News feed article types to keep, as the integer ids the feed API uses.
  # Defaults to the set the RCAC news API uses; configure an empty string to
  # keep every article regardless of type.
  #
  # Not a `site_string_configs` key: this name is taken by the method.
  #
  # @return [Array<Integer>] empty means keep every article
  def news_type_ids
    raw = site_config(:news_type_ids)
    raw = '1,2,3,6,7' if raw.nil?
    raw.to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i)
  end

  # GRES token -> display name, parsed from the `gpu_models` config, which is a
  # comma-separated list of `token:label` pairs.
  #
  # Reads the generated `gpu_models` accessor rather than `site_config_list`:
  # `site_config` consults only the environment and the external config file,
  # so a key that carries a default in `site_string_configs` loses that default
  # when read that way.
  #
  # @return [Hash{String=>String}]
  def gpu_model_map
    gpu_models.to_s.split(',').map(&:strip).reject(&:empty?).each_with_object({}) do |pair, h|
      token, label = pair.split(':', 2)
      h[token.to_s.strip] = label.to_s.strip if token.present? && label.present?
    end
  end

  # @return [String, nil] home directory for the given user, if configured
  def home_dir_for(user)
    home_dir_template&.gsub('$USER', user.to_s).presence
  end

  # Compiled form of `node_name_pattern`. An unusable pattern is logged and
  # treated as unset rather than raising, so a typo in site config cannot take
  # the Cluster Status page down.
  #
  # @return [Regexp, nil] nil means match every node
  def node_name_regexp
    pattern = node_name_pattern
    return nil if pattern.blank?

    Regexp.new(pattern)
  rescue RegexpError => e
    Rails.logger.warn("Invalid node_name_pattern #{pattern.inspect}: #{e.message}; showing all nodes")
    nil
  end

  # @return [Boolean] whether per-job jobstats metrics can be collected
  def jobstats_enabled?
    jobstats_python.present? && jobstats_script.present?
  end

  # @return [Boolean] whether the news feed widget has an endpoint to call
  def news_feed_enabled?
    news_feed_url.present?
  end

  # @return [Boolean] whether the Storage widget has a command to report quotas
  def quota_command_enabled?
    quota_command.present?
  end

  # Which TRES an account's balance is recorded under. Allocations denominated
  # in GPU time are held under a different TRES from CPU ones, and sites tell
  # them apart by account naming -- `gpu_account_pattern` is matched against the
  # account name as a regular expression (so a plain "-gpu" matches any account
  # containing it, and "-gpu\z" only a suffix).
  #
  # @param account [String] Slurm account name
  # @return [String] TRES key to read the balance from
  def account_tres_for(account)
    pattern = gpu_account_pattern
    return cpu_account_tres if pattern.blank?

    Regexp.new(pattern).match?(account.to_s) ? gpu_account_tres : cpu_account_tres
  rescue RegexpError => e
    Rails.logger.warn("Invalid gpu_account_pattern #{pattern.inspect}: #{e.message}")
    cpu_account_tres
  end

  # @return [String, nil] scratch directory for the given user, if configured
  def scratch_dir_for(user)
    scratch_dir_template&.gsub('$USER', user.to_s).presence
  end

  # @return [String] memoized version string
  def app_version
    @app_version ||= (version_from_file(Rails.root) || version_from_git(Rails.root) || "Unknown").strip
  end

  # @return [String] memoized version string
  def ood_version
    @ood_version ||= (ood_version_from_env || version_from_file('/opt/ood') || version_from_git('/opt/ood') || "Unknown").strip
  end

  def ood_bc_ssh_to_compute_node
    to_bool(ENV['OOD_BC_SSH_TO_COMPUTE_NODE'] || true)
  end

  # @return [String, nil] version string from git describe, or nil if not git repo
  def version_from_git(dir)
    Dir.chdir(Pathname.new(dir)) do
      version = `git describe --always --tags 2>/dev/null`
      version.blank? ? nil : version
    end
  rescue Errno::ENOENT
    nil
  end

  def login_clusters
    OodCore::Clusters.new(
      OodAppkit.clusters
        .select(&:allow?)
        .reject { |c| c.metadata.hidden }
        .select(&:login_allow?)
    )
  end

  # clusters you can submit jobs to
  def job_clusters
    @job_clusters ||= OodCore::Clusters.new(
      OodAppkit.clusters
        .select(&:job_allow?)
        .reject { |c| c.metadata.hidden }
    )
  end

  # @return [String, nil] version string from VERSION file, or nil if no file avail
  def version_from_file(dir)
    file = Pathname.new(dir).join("VERSION")
    file.read if file.file?
  end

  def ood_version_from_env
    ENV['OOD_VERSION'] || ENV['ONDEMAND_VERSION']
  end

  # The app's configuration root directory
  # @return [Pathname] path to configuration root
  def config_root
    Pathname.new(ENV["OOD_APP_CONFIG_ROOT"] || "/etc/ood/config/apps/dashboard")
  end

  def load_external_config?
    to_bool(ENV['OOD_LOAD_EXTERNAL_CONFIG'] || (rails_env == 'production'))
  end

  # The root directory that holds configuration information for Batch Connect
  # apps (typically each app will have a sub-directory underneath this)
  def bc_config_root
    Pathname.new(ENV["OOD_BC_APP_CONFIG_ROOT"] || "/etc/ood/config/apps")
  end

  def load_external_bc_config?
    to_bool(ENV["OOD_LOAD_EXTERNAL_BC_CONFIG"] || (rails_env == "production"))
  end

  # The paths to the JSON files that store the quota information
  # Can be URL or File path. colon delimited string; though colon in URL is
  # ignored if URL has format: scheme://path (colons preceeding // are ignored)
  #
  # /path/to/quota.json:https://osc.edu/quota.json
  #
  #
  # @return [Array<String>] quota paths
  def quota_paths
    # regex uses negative lookahead to ignore : preceeding //
    ENV.fetch("OOD_QUOTA_PATH", "").strip.split(/:(?!\/\/)/)
  end

  # The threshold for determining if there is sufficient quota remaining
  # @return [Float] threshold factor
  def quota_threshold
    ENV.fetch("OOD_QUOTA_THRESHOLD", 0.95).to_f
  end

  # The paths to the JSON files that store the balance information
  # Can be URL or File path. colon delimited string; though colon in URL is
  # ignored if URL has format: scheme://path (colons preceeding // are ignored)
  #
  # /path/to/balance.json:https://osc.edu/balance.json
  #
  #
  # @return [Array<String>] balance paths
  def balance_paths
    # regex uses negative lookahead to ignore : preceeding //
    ENV.fetch("OOD_BALANCE_PATH", "").strip.split(/:(?!\/\/)/)
  end

  # The threshold for determining if there is sufficient balance remaining
  # @return [Float] threshold factor
  def balance_threshold
    ENV.fetch("OOD_BALANCE_THRESHOLD", 0).to_f
  end

  # The XMoD host
  # @return [String, null] the host, or null if not set
  def xdmod_host
    ENV["OOD_XDMOD_HOST"]
  end

  # Whether or not XDMoD integration is enabled
  # @return [Boolean]
  def xdmod_integration_enabled?
    xdmod_host.present?
  end

  # Support ticket configuration
  def support_ticket_enabled?
    config.has_key?(:support_ticket) || config.fetch(:profiles, {}).any? { |_, profile| profile.has_key?(:support_ticket) }
  end

  # Globus configuration
  def globus_endpoints
    config.fetch(:globus_endpoints, nil)
  end

  # Load the dotenv local files first, then the /etc dotenv files and
  # the .env and .env.production or .env.development files.
  #
  # Doing this in two separate loads means OOD_APP_CONFIG_ROOT can be specified in
  # the .env.local file, which will specify where to look for the /etc dotenv
  # files. The default for OOD_APP_CONFIG_ROOT is /etc/ood/config/apps/myjobs and
  # both .env and .env.production will be searched for there.
  def load_dotenv_files
    # .env.local first, so it can override OOD_APP_CONFIG_ROOT
    Dotenv.load(*dotenv_local_files)

    # load the rest of the dotenv files
    Dotenv.load(*dotenv_files)

    # load overloads
    Dotenv.overload(*(overload_files(dotenv_files)))
    Dotenv.overload(*(overload_files(dotenv_local_files)))
  end

  def dev_apps_root_path
    Pathname.new(ENV["OOD_DEV_APPS_ROOT"] || "/dev/null")
  end

  def app_development_enabled?
    return @app_development_enabled if defined? @app_development_enabled
    to_bool(ENV['OOD_APP_DEVELOPMENT'] || DevRouter.base_path.directory? || DevRouter.base_path.symlink?)
  end
  alias_method :app_development_enabled, :app_development_enabled?

  def app_sharing_enabled?
    return @app_sharing_enabled if defined? @app_sharing_enabled
    @app_sharing_enabled = to_bool(ENV['OOD_APP_SHARING'])
  end
  alias_method :app_sharing_enabled, :app_sharing_enabled?

  def batch_connect_global_cache_enabled?
    to_bool(ENV["OOD_BATCH_CONNECT_CACHE_ATTR_VALUES"] || true )
  end

  def developer_docs_url
    ENV['OOD_DASHBOARD_DEV_DOCS_URL'] || "https://go.osu.edu/ood-app-dev"
  end

  def dataroot
    # copied from OodAppkit::AppConfig#set_default_configuration
    # then modified to ensure dataroot is never nil
    #
    # FIXME: note that this would be invalid if the dataroot where
    # overridden in an initializer by modifying OodAppkit.dataroot
    # Solution: in a test, add a custom initializer that changes this, then verify it has
    # no effect or it affects both.
    #
    root = ENV['OOD_DATAROOT'] || ENV['RAILS_DATAROOT']
    if rails_env == "production"
      root ||= "~/#{ENV['OOD_PORTAL'] || 'ondemand'}/data/#{ENV['APP_TOKEN'] || 'sys/dashboard'}"
    else
      root ||= app_root.join("data")
    end

    Pathname.new(root).expand_path
  end

  def locale
    (ENV['OOD_LOCALE'] || 'en').to_sym
  end

  def locales_root
    Pathname.new(ENV['OOD_LOCALES_ROOT'] || "/etc/ood/config/locales")
  end

  # Set the login host in the Native Instructions VNC session partial
  def native_vnc_login_host
    ENV['OOD_NATIVE_VNC_LOGIN_HOST']
  end

  # Set the global configuration directory
  def config_directory
    Pathname.new(ENV['OOD_CONFIG_D_DIRECTORY'] || "/etc/ood/config/ondemand.d")
  end

  # Setting terminal functionality in files app
  def files_enable_shell_button
    to_bool(config.fetch(:files_enable_shell_button, true))
  end

  # Report performance of activejobs table rendering
  def console_log_performance_report?
    dataroot.join("debug").file? || rails_env != 'production'
  end

  def can_access_activejobs?
    can_access_core_app? 'activejobs'
  end

  def can_access_files?
    can_access_core_app? 'files'
  end

  def can_access_file_editor?
    can_access_core_app? 'file-editor'
  end

  def can_access_projects?
    can_access_core_app? 'projects'
  end

  # Maximum file upload size that nginx will allow from clients in bytes
  #
  # @example No maximum upload size supplied.
  #   file_upload_max #=> "10737420000"
  # @example 20 gigabyte file size upload limit.
  #   file_upload_max #=> "21474840000"
  # @return [String] Maximum upload size for nginx.
  def file_upload_max
    [ENV['FILE_UPLOAD_MAX']&.to_i, ENV['NGINX_FILE_UPLOAD_MAX']&.to_i].compact.min || 10737420000
  end

  # The timeout (seconds) for "generating" a .zip from a directory.
  #
  # Default for OOD_DOWNLOAD_DIR_TIMEOUT_SECONDS is "5" (seconds).
  # @return [Integer]
  def file_download_dir_timeout
    ENV['OOD_DOWNLOAD_DIR_TIMEOUT_SECONDS']&.to_i || 5
  end

  # The maximum size of a .zip file that can be downloaded.
  #
  # Default for OOD_DOWNLOAD_DIR_MAX is 10*1024*1024*1024 bytes.
  # @return [Integer]
  def file_download_dir_max
    ENV['OOD_DOWNLOAD_DIR_MAX']&.to_i || 10737418240
  end

  def allowlist_paths
    (ENV['OOD_ALLOWLIST_PATH'] || ENV['WHITELIST_PATH'] || "").split(':').map{ |s| Pathname.new(s) }
  end

  # default value for opening apps in new window
  # that is used if app's manifest doesn't specify
  # if not set default is true
  #
  # @return [Boolean] true if by default open apps in new window
  def open_apps_in_new_window?
    if ENV['OOD_OPEN_APPS_IN_NEW_WINDOW']
      to_bool(ENV['OOD_OPEN_APPS_IN_NEW_WINDOW'])
    else
      true
    end
  end

  # How many days before a Session record is considered old and ready to delete
  def ood_bc_card_time
    ood_bc_card_time = ENV['OOD_BC_CARD_TIME']
    return 7 if ood_bc_card_time.blank? || /^([+-]\d+|\d+)/.match(ood_bc_card_time.to_s).nil?

    ood_bc_card_time_int = ood_bc_card_time.to_i
    (ood_bc_card_time_int < 0) ? 0 : ood_bc_card_time_int
  end

  def config
    @config ||= read_config
  end

  # Content security policy value for 'script-src'
  def script_sources
    sources = [:self]
    sources << 'https://www.googletagmanager.com' unless google_analytics_tag_id.nil?

    sources
  end

  # Content security policy value for 'connect-src'
  def connect_sources
    sources = [:self]
    sources << 'https://www.google-analytics.com' unless google_analytics_tag_id.nil?

    sources
  end

  private

  def can_access_core_app?(name)
    app_dir = Rails.root.realpath.parent.join(name)
    app_dir.directory? && app_dir.join('manifest.yml').readable?
  end

  def read_config
    files = Pathname.glob(config_directory.join("*.{yml,yaml,yml.erb,yaml.erb}"))
    files.sort.each_with_object({}) do |f, conf|
      begin
        content = ERB.new(f.read, trim_mode: "-").result(binding)
        yml = YAML.safe_load(content, aliases: true) || {}
        conf.deep_merge!(yml.deep_symbolize_keys)
      rescue => e
        Rails.logger.error("Can't read or parse #{f} because of error #{e}")
      end
    end
  end

  # The environment
  # @return [String] "development", "test", or "production"
  def rails_env
    ENV['RAILS_ENV'] || ENV['RACK_ENV'] || "development"
  end

  # The app's root directory
  # @return [Pathname] path to app root
  def app_root
    Pathname.new(File.expand_path("../../",  __FILE__))
  end

  def dotenv_local_files
    [
      app_root.join(".env.#{rails_env}.local"),
      (app_root.join(".env.local") unless rails_env == "test"),
    ].compact
  end

  def dotenv_files
    [
      (config_root.join("env") if load_external_config?),
      app_root.join(".env.#{rails_env}"),
      app_root.join(".env")
    ].compact
  end

  # reverse list and suffix every path with '.overload'
  def overload_files(files)
    files.reverse.map {|p| p.sub(/$/, '.overload')}
  end

  FALSE_VALUES = [nil, false, '', 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', 'no', 'NO'].freeze

  # Bool coersion pulled from ActiveRecord::Type::Boolean#cast_value
  #
  # @return [Boolean] false for falsy value, true for everything else
  def to_bool(value)
    !FALSE_VALUES.include?(value)
  end

  # private method to add the boolean_config methods to this instances
  def add_boolean_configs
    boolean_configs.each do |cfg_item, default|
      define_singleton_method(cfg_item.to_sym) do
        e = ENV["OOD_#{cfg_item.to_s.upcase}"]

        if e.nil?
          config.fetch(cfg_item, default)
        else
          to_bool(e.to_s)
        end
      end
    end.each do |cfg_item, _|
      define_singleton_method("#{cfg_item}?".to_sym) do
        send(cfg_item)
      end
    end
  end

  def add_string_configs
    string_configs.each do |cfg_item, default|
      define_singleton_method(cfg_item.to_sym) do
        e = ENV["OOD_#{cfg_item.to_s.upcase}"]

        e.nil? ? config.fetch(cfg_item, default) : e.to_s
      end
    end.each do |cfg_item, _|
      define_singleton_method("#{cfg_item}?".to_sym) do
        send(cfg_item).nil?
      end
    end
  end
end
