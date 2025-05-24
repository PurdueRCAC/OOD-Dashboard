class JobController < ApplicationController
    def show
      @job_id = params[:jobid]
      @session = BatchConnect::Session.all.find { |s| s.job_id == @job_id }
    end
  end 