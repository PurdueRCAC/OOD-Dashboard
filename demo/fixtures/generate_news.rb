#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates demo/fixtures/news.json with dates anchored to "now", so the
# announcements widget always has a current outage, an upcoming maintenance
# window, and some past items. Run this if the demo's news starts looking old:
#   ruby demo/fixtures/generate_news.rb
#
# Types mirror the news API the widget expects:
#   1 Outages and Maintenance, 2 Announcements, 3 Science Highlights,
#   6 Outages, 7 Maintenance
require 'json'
require 'time'

now = Time.now
fmt  = ->(t) { t.strftime('%Y-%m-%dT%H:%M:%S') }
nice = ->(t) { t.strftime('%B %-d, %Y') }

def article(id, type, headline, body, start_t, end_t, fmt, nice, updates: [])
  {
    'id' => id,
    'newstypeid' => type,
    'headline' => headline,
    'uri' => "https://openondemand.org/demo-news/#{id}",
    'formatteddate' => nice.call(start_t),
    'formattedbody' => body,
    'datetimenews' => fmt.call(start_t),
    'datetimenewsend' => end_t ? fmt.call(end_t) : nil,
    'resources' => [{ 'name' => 'Demo Cluster' }],
    'updates' => updates
  }
end

data = [
  article(101, 6, 'Scratch filesystem degraded performance',
          '<p>We are investigating elevated latency on the <code>/scratch</code> filesystem. ' \
          'Jobs performing heavy I/O may run slower than usual. No data loss is expected.</p>',
          now - 5 * 3600, now + 7 * 3600, fmt, nice,
          updates: [
            { 'formattedbody' => '<p>A failed metadata server has been taken out of rotation. Performance is recovering.</p>',
              'datetimecreated' => fmt.call(now - 2 * 3600),
              'formattedcreateddate' => nice.call(now - 2 * 3600) }
          ]),
  article(102, 7, 'Scheduled maintenance: cluster unavailable',
          '<p>The cluster will be offline for quarterly maintenance. Running jobs will be ' \
          'terminated; queued jobs remain queued and start after the outage.</p>',
          now + 9 * 86_400, now + 10 * 86_400, fmt, nice),
  article(103, 2, 'New H100 nodes available in the ai partition',
          '<p>Six additional nodes with 8x NVIDIA H100 accelerators have joined the ' \
          '<code>ai</code> partition. Request them with <code>--gres=gpu:h100:1</code>.</p>',
          now - 3 * 86_400, nil, fmt, nice),
  article(104, 2, 'Open OnDemand upgraded to 3.1',
          '<p>The portal has been upgraded. Interactive sessions started before the upgrade ' \
          'are unaffected.</p>',
          now - 12 * 86_400, nil, fmt, nice),
  article(105, 3, 'Researchers model protein folding at scale',
          '<p>A campus group used 1.2 million core-hours on the cluster to model folding ' \
          'pathways, with results published this month.</p>',
          now - 21 * 86_400, nil, fmt, nice),
  article(106, 1, 'Login node reboot completed',
          '<p>Rolling reboots to apply kernel security updates have finished. All login ' \
          'nodes are back in service.</p>',
          now - 30 * 86_400, now - 29 * 86_400, fmt, nice)
]

out = File.expand_path('news.json', __dir__)
File.write(out, JSON.pretty_generate('data' => data) + "\n")
puts "wrote #{out} (#{data.size} articles)"
