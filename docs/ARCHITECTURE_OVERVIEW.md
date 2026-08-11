# OOD Dashboard Architecture Overview

This document maps the dashboard widgets and features to their controlling files/scripts.

## Dashboard Widgets

### Announcements Widget

- **Widget View:** `app/views/widgets/_news_feed.erb`
- **API Controller:** `app/controllers/api/news_feed_controller.rb`
- **API Route:** `GET /api/news_feed`
- **JavaScript Function:** `load_news_feed()` (defined inline in widget)
- **Data Source:** External JSON news API (`OOD_NEWS_FEED_URL`); a local fixture
  in demo mode
- **Cache Duration:** 30 minutes (server-side), 1 hour (client-side)

### Job Queue Widget

- **Widget View:** `app/views/widgets/_job_queue.erb`
- **API Controller:** `app/controllers/api/job_queue_controller.rb`
- **API Route:** `GET /api/job_queue`
- **JavaScript Function:** `load_job_queue()` (defined inline in widget)
- **Data Source:** SLURM squeue command
- **Cache Duration:** 5 seconds
- **Links To:** `/myjobs` (My Jobs page)

### Partition Status Widget

- **Widget View:** `app/views/widgets/_partition_status.erb`
- **API Controller:** `app/controllers/api/partition_status_controller.rb`
- **API Route:** `GET /api/partition_status`
- **JavaScript Function:** `load_partition_status()` (defined inline in widget)
- **Data Source:** SLURM sinfo command
- **Cache Duration:** 60 seconds (server-side), 30 seconds (client-side)
- **Displays:** Partition state (UP/DOWN/DRAIN), core/node/GPU utilization

### Account List Widget

- **Widget View:** `app/views/widgets/_account_list.erb`
- **API Controller:** `app/controllers/api/account_list_controller.rb`
- **API Route:** `GET /api/account_list`
- **JavaScript Function:** `load_account_list()` (defined inline in widget)
- **Related API:** `app/controllers/api/gpu_hour_summary_controller.rb` (for exports)
- **Data Source:** SLURM account/user allocation data
- **Cache Duration:** 1 minute
- **Features:** CPU/GPU usage per allocation, export to CSV/Excel

### Disk Usage Widget

- **Widget View:** `app/views/widgets/_disk_usage.erb`
- **API Controller:** `app/controllers/api/disk_usage_controller.rb`
- **API Route:** `GET /api/disk_usage`
- **JavaScript Function:** `load_disk_usage()` (defined inline in widget)
- **Data Source:** Filesystem quota commands
- **Cache Duration:** 60 seconds (server-side), 5 minutes (client-side)
- **Displays:** Home/scratch/depot storage usage and file counts
- **Links To:** Files browser

### Balance Usage Widget

- **Widget View:** `app/views/widgets/_balance_usage.erb`
- **API Controller:** `app/controllers/api/balance_usage_controller.rb`
- **API Route:** `GET /api/balance_usage`
- **JavaScript Function:** `load_balance_usage()` (defined inline in widget)
- **Related API:** `app/controllers/api/balance_summary_controller.rb`
  (`GET /api/balance_summary`)
- **Data Source:** SLURM accounting via `scontrol show assoc` and `sacctmgr`
- **Cache Duration:** 1 hour (server-side), 10 minutes (client-side)
- **Displays:** Service-unit balance and usage per allocation
- **Notes:** Reads SLURM directly rather than OOD's balance JSON. Which TRES an
  allocation is denominated in is configurable — see `OOD_GPU_ACCOUNT_PATTERN`
  in `.env.local.example`.

## Other Dashboard Features

### My Jobs Page

- **Controller:** `app/controllers/my_jobs_controller.rb`
- **Routes:** `GET /myjobs`, `GET /myjobs/json`, `DELETE /myjobs`
- **Views:** `app/views/my_jobs/index.html.erb`

### Job Overview Page

- **Controller:** `app/controllers/job_controller.rb`
- **Route:** `GET /job/:jobid`
- **Views:** `app/views/job/show.html.erb`
- **API:** `app/controllers/api/jobs_controller.rb`

### Node Overview Page

- **Controller:** `app/controllers/nodes_controller.rb`
- **Route:** `GET /nodes/:name`
- **Views:** `app/views/nodes/show.html.erb`
- **API:** `app/controllers/api/nodes_controller.rb`

### Cluster Status Page

- **Controller:** `app/controllers/cluster_status_controller.rb`
- **Route:** `GET /cluster_status`
- **API:** `app/controllers/api/cluster_status_controller.rb`
- **Views:** `app/views/cluster_status/index.html.erb`

### Performance Metrics Page

- **Controller:** `app/controllers/performance_metrics_controller.rb`
- **Route:** `GET /performance_metrics`
- **API:** `app/controllers/api/performance_metrics_controller.rb`
- **Views:** `app/views/performance_metrics/index.html.erb`

### Dashboard Guide Page

- **Controller:** `app/controllers/help_controller.rb` (`dashboard_guide`)
- **Route:** `GET /help/dashboard-guide`
- **Views:** `app/views/help/dashboard_guide.html.erb`
- **Notes:** In-portal help explaining each widget. Static — no API controller.