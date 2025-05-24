class NodesController < ApplicationController
  def show
    @node_name = params[:name]
  end
end 