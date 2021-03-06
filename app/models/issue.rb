require 'config/config'
require 'ostruct'

class Issue < ActiveRecord::Base
  extend FriendlyId

  OPEN          = 1
  IN_PROGRESS   = 2
  ACCEPTED      = 3
  FIXED         = 4
  DELETED       = 5
  RE_OPENED     = 6

  TRANS_KEYS = ['none','open','in_progress', 'accepted','fixed','deleted','re_opened']

  default_scope where('status <> 5')

  attr_accessor :image_url, :short_desc, :issue_url
  attr_accessible  :title, :category, :city, :description, :user, :lat, :long, :status, :vote_count, :view_count, :comment_count, :share_count, :created_at

  belongs_to 	:user
  belongs_to  :category
  belongs_to	:city

  has_many		:comments, :dependent => :destroy
  has_many    :images, :dependent => :destroy
  has_many    :votes, :dependent => :destroy
  has_many    :unique_views, :dependent => :destroy
  
  friendly_id :title, :use => [:slugged]

  def mark_as_viewed(user_uniq_cookie_id) 
    uniq_view = self.unique_views.where(:session => user_uniq_cookie_id).first

    if (uniq_view)
      # count if 1hour diff (config file)
      if (Config::Configuration.get(:misc, :unique_view_epsilon).to_f < (Time.now - uniq_view.viewed_at))
        self.session_view_count += 1
        uniq_view.viewed_at = Time.now
        uniq_view.save!
      end
    else
      UniqueView.create({:session => user_uniq_cookie_id, :issue_id => self.id, :viewed_at => Time.now })
      self.session_view_count += 1
    end

    # Non unique view count
    self.view_count += 1
    self.save!
  end

  def setup_json_attributes!()
    @image_url = self.images.first.image.thumb.url
    @short_desc = ApplicationController.helpers.truncate(self.description, :length => 200)
    @issue_url = Rails.application.routes.url_helpers.issue_path(self.friendly_id)
  end

  def self.get_geo_issues(south_west_geo, north_east_geo, limit)
    sw_lat = south_west_geo[:lat]
    sw_long = south_west_geo[:long]
    ne_lat = north_east_geo[:lat]
    ne_long = north_east_geo[:long]


    return Issue.where('lat > ? AND lat < ? AND long > ? AND long < ?', sw_lat, ne_lat, sw_long, ne_long).limit(limit)  
  end

  def get_status
    trans_key = TRANS_KEYS[self.status]
    I18n.t("issues.status.#{trans_key}")
  end

  def self.all_statuses
    results = []
    6.downto(1) do |i|
      trans_key = TRANS_KEYS[i]
      results << OpenStruct.new(:id => i, :name => I18n.t("issues.status.#{trans_key}"))
    end
    results
  end

  def self.user_statuses
    results = []
    [1,2,3,4,6].each do |i|
      trans_key = TRANS_KEYS[i]
      results << OpenStruct.new(:id => i, :name => I18n.t("issues.status.#{trans_key}"))
    end

    results
  end

  def as_json(options={})
    # also can be solved by adding :methods to options hash
    response = super(options)
    response[:image_url] = self.image_url
    response[:short_desc] = self.short_desc
    response[:issue_url] = self.issue_url
    response
  end
  
  def self.get_issues(params, limit=9, offset=0)
  	query = Array.new
    values = Hash.new

    # Order
    order_by = 'created_at desc'



    # Get category, status and city params
    if (!params[:category].blank?)
      #query << 'category_id = :category_id'
      #values[:category_id] = params[:category]
      query << 'category_id IN (:category_ids)'
      # category id + all its subcategory ids
      values[:category_ids] = [params[:category]].concat(Category.subcategories_ids(params[:category]))
    end

    if (!params[:status].blank?)
      query << 'status = :status'
      values[:status] = params[:status]
    end

    if (!params[:city].blank?)
      query << 'city_id = :city_id'
      values[:city_id] = params[:city]
    end

    if (!params[:date].blank?)
      date = params[:date]

      if (date == 'today')
        start_time = Time.now.beginning_of_day
        end_time = Time.now.end_of_day
      elsif (date == 'week')
        start_time = Time.now.beginning_of_week
        end_time = Time.now.end_of_week
      elsif (date == 'month')
        start_time = Time.now.beginning_of_month
        end_time = Time.now.end_of_month
      end

      query << '(created_at > :start_time AND created_at < :end_time)'
      values[:start_time] = start_time
      values[:end_time] = end_time 
    end

    if (!params[:featured].blank?)
      sort_by = params[:featured]

      if (sort_by == 'viewed')
        order_by = 'view_count desc'
      elsif (sort_by == 'votes')
        order_by = 'vote_count desc'
      elsif (sort_by == 'discussed')
        order_by = 'comment_count desc'
      end
    end

    if (query.empty?)
  		@issues_relation = Issue
	  else
		  @issues_relation = Issue.where(query.join(' AND '), values)
    end
    
    return @issues_relation.limit(limit).offset(offset).order(order_by).includes([:user, :city, :category, :images, :category])
  end
end