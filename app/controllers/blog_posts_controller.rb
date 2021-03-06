class BlogPostsController < ApplicationController
  respond_to :json, :xml
  layout false

  skip_before_filter :verify_authenticity_token, only: [:update]
  before_filter :validate_api_admin, only: [:update]

  skip_before_filter :require_login

  def index
    render json: BlogPost.published.order('publication_date DESC').as_json
  end

  def update
    notification = Salesforce::Notification.new(request.body.read)
    salesforce_blog_post = Salesforce::Listing::BlogPost.new(notification)

    blog_post = BlogPost.from_salesforce(salesforce_blog_post)

    if blog_post.save
      respond_to do |format|
        format.xml  { render 'salesforce/success', layout: false }
      end
    else
      respond_to do |format|
        format.xml  { render xml: "", status: 422 }
      end
    end
  end

  def sync

  end
end