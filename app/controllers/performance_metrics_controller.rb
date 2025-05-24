class PerformanceMetricsController < ApplicationController
    def index
      render template: "performance_metrics/index"
    end
  end