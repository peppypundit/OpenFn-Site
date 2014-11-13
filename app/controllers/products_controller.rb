class ProductsController < ApplicationController
  respond_to :json
  layout false

  def index
    render json: Product.order('name').as_json
  end

  def update
    raise params.inspect

    respond_to do |format|
      format.xml  { render xml: "" }
    end
  end
end