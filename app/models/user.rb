# encoding: UTF-8
class User < ActiveRecord::Base

  include SoftDelete

  ROLE_GUEST            = 1
  ROLE_USER             = 2
  ROLE_COMMUNITY_ADMIN  = 3
  ROLE_SSG_ADMIN        = 4
  
  GUEST_USER = User.new(:role => ROLE_GUEST, :first_name => 'Guest', :locale => I18n.locale)

  LOCALES = [:bs, :en]

  has_many    :issues
  has_many    :votes
  has_many    :follows

  belongs_to  :city
  belongs_to  :image

  DEF_LAT, DEF_LON, DEF_ZOOM_LVL, CITY_ZOOM = 43.855078, 18.395748, 10, 13

  default_scope where(:deleted => false)
  

  def users_lat_long
    self.city.nil? ? [DEF_LAT, DEF_LON] : [self.city.lat.to_f, self.city.long.to_f]
  end

  def users_zoom
    self.city.nil? ? DEF_ZOOM_LVL : CITY_ZOOM
  end

  def get_city_id
    self.city.nil? ? -1 : self.city.id
  end

  def get_follows
    return self.follows.order(:type)
  end
  
  # only parent categories are returned here
  def get_categories
    get_sub_categories(nil)
  end

  def get_sub_categories(parent_id)
    Category.where(:parent_id => parent_id).all
  end

  def get_all_categories()
    parent_categories = get_categories()
    results = []
    parent_categories.each do |cat|
      results << OpenStruct.new(:id => cat.id, :name => cat.name)
      sub_categories = get_sub_categories(cat.id)
      sub_categories.each do |sub_cat|
        results << OpenStruct.new(:id => sub_cat.id, :name => "·· #{sub_cat.name}")
      end
    end

    results
  end

  def get_cities
    return City.all
  end

  def self.get_admin_roles
    results = []
    results << OpenStruct.new( :name => 'Korisnik', :value => ROLE_USER)
    results << OpenStruct.new( :name => 'Administrativni Korisnik', :value => ROLE_COMMUNITY_ADMIN)
    results << OpenStruct.new( :name => 'SSG Admin', :value => ROLE_SSG_ADMIN)
    results
  end

  def self.get_locales
    results = []

    LOCALES.each do |localee|
      results << OpenStruct.new( :name => I18n.t("shared.locale.#{localee}"), :value => localee)
    end

    results
  end

  def fbuser?
    return !self.fb_id.nil?
  end

  def ssg_admin?
    return (self.role == ROLE_SSG_ADMIN)
  end
  
  def community_admin?
    return (self.role == ROLE_COMMUNITY_ADMIN)
  end
  
  def display_name
    return self.username
  end

  def is_good_password?(pwd)
    return self.password_hash.eql? Digest::SHA256.hexdigest(pwd)
  end

  def full_name
    fname = "#{self.first_name} #{self.last_name}"
    if fname.blank?
      fname = self.username
    end
    return fname
  end

  def avatar
    fbuser? ? "http://graph.facebook.com/#{fb_id}/picture" : '/assets/no_avatar.png'
  end

  def formated_website
    if self.website.match(/^(http|https):\/\/.*/ix)
      return self.website
    else
      return "http://#{website}"
    end
  end
  
  def comment_on_issue(issue_id, text)
    ActiveRecord::Base.transaction do    
      issue = Issue.find(issue_id)
      issue.comments << Comment.new(:text => text, :user => self)
      issue.comment_count += 1
      issue.save
    end
  end

  def vote_for(issue_id)
    ActiveRecord::Base.transaction do
      issue = Issue.find(issue_id)
      # You can't vote for your issues
      if (issue.user_id != self.id)
        vote = Vote.where(:user_id => self.id, :issue_id => issue.id).first
        if (issue && vote.nil?)
          Vote.create(:user => self, :issue => issue)
        end
        issue.vote_count += 1
        issue.save
      end
    end
  end

  def change_status_for(issue_id, status)
    ActiveRecord::Base.transaction do
      issue = Issue.find(issue_id)
      # You can't vote for your issues
      if (issue.user_id == self.id || self.ssg_admin?)
        issue.status = status.to_i
        issue.save
      end
    end
  end

  def unvote_for(issue_id)
    ActiveRecord::Base.transaction do
      issue = Issue.find(issue_id)
      # You can't vote for your issues
      if (issue.user_id != self.id)
        vote = Vote.where(:user_id => self.id, :issue_id => issue.id).first
        if (vote)
          vote.destroy
        end
        issue.vote_count -= 1
        if (issue.vote_count < 0)
          issue.vote_count = 0
        end
        issue.save
      end
    end
  end
  
  def follow(issue_id)
    issue = Issue.find(issue_id)
    follow = FollowIssue.where(:user_id => self.id, :follow_ref_id => issue.id).first
    if (issue && follow.nil?)
      FollowIssue.create(:user => self, :follow_issue => issue)
    end
  end
  
  def follow_user(user_id)
    user = User.find(user_id)
    follow = FollowUser.where(:user_id => self.id, :follow_ref_id => user.id).first
    if (user && follow.nil?)
      FollowUser.create(:user => self, :follow_user => user)
    end
  end
  
  def create_issue(title, category_id, city_id, descripion, lat, long, image_ids)
    ActiveRecord::Base.transaction do
      category = Category.find(category_id)
      city = City.find(city_id)

      issue = Issue.new({ 
        :user => self, 
        :title => title, 
        :description => descripion, 
        :category => category, 
        :city => city,
        :lat => lat,
        :long => long
      })
      issue.save

      Image.update_all({ :issue_id => issue.id}, { :id => image_ids })

      return issue
    end
  end

  def create_issue_seed(title, category_id, city_id, descripion, lat, long, image_ids, status, created_ts, vote_c, view_c, comments_c, share_c)
    ActiveRecord::Base.transaction do
      category = Category.find(category_id)
      city = City.find(city_id)

      issue = Issue.new({ 
        :user => self, 
        :title => title, 
        :description => descripion, 
        :category => category, 
        :city => city,
        :lat => lat,
        :long => long,
        :status => status,
        :vote_count => vote_c,
        :view_count => view_c,
        :comment_count => comments_c,
        :share_count => share_c,
        :created_at => created_ts
      })
      issue.save

      Image.update_all({ :issue_id => issue.id}, { :id => image_ids })

      return issue
    end
  end
  
  def guest?
    return self.role & ROLE_GUEST == ROLE_GUEST
  end

  def user_type
    case role
    when ROLE_GUEST
      "Guest"
    when ROLE_USER
      "Korisnik"
    when ROLE_COMMUNITY_ADMIN
      "Administrativni Korisnik"
    when ROLE_SSG_ADMIN
      "SSG Admin"
    else
      "Rola nije definisana"
    end
  end

  def self.exists?(username, pwd)
    usr = User.find_by_username(username)
    if (usr && usr.password_hash == Digest::SHA256.hexdigest(pwd))
      return usr
    end
    
    return nil
  end

  def self.send_community_admin_mails(url, city_id)
    users = User.where(:city_id => city_id, :role => ROLE_COMMUNITY_ADMIN).all
    users.each do |user|
      UserMailer.created(user, url).deliver
    end

    # mail goes to predfined user to be notifed about all emails
    UserMailer.notify_created(City.find(city_id), url).deliver
  end

  #
  # Returns user only with ssg admin
  #
  def self.user_ssg_admin?(username, pwd)
    usr = exists?(username, pwd)
    usr && usr.active && (usr.ssg_admin? || usr.community_admin?) ? usr : nil
  end
  
  def self.guest_user
    return GUEST_USER
  end
  
  #
  # Login/Signup/Signout methods
  #
  def self.fb_client
    return OAuth2::Client.new(Config::Configuration.get(:fb, :application_id), Config::Configuration.get(:fb, :secret_key), :site => Config::Configuration.get(:fb, :site_url))
  end

  def self.create_fb_user(token, email, fb_id, last_name, first_name, username, is_active = true, role = User::ROLE_USER)
    user = User.new
    user.email = email
    user.uuid = UUIDTools::UUID.random_create.to_s
    user.fb_id = fb_id
    user.fb_token = token
    user.username = username
    user.last_name = last_name
    user.first_name = first_name
    user.active = is_active
    user.role = role
    user.locale = I18n.default_locale
    user.save
    
    return user
  end

  def self.create_ssg_user(username, email, pwd, city_id)

    user = User.find_by_username(username)

    # New user
    if user.nil?
      user = User.new(:active => false)
    end

    # Inactive user - send email again
    if (user.active == false)
      user.username = username
      user.email = email
      user.password_hash = Digest::SHA256.hexdigest(pwd)
      user.uuid = UUIDTools::UUID.random_create.to_s
      user.active = false
      user.role = ROLE_USER
      user.city_id = city_id
      user.locale = I18n.default_locale

      return user
    # Active user
    else
      return nil
    end
  end

  def self.verify(id, uuid)
    user = User.where("id = ? and uuid = ?", id, uuid).first
    # Only inactive users can be activated
    if (!user.nil? && user.active == false)
      user.active = true;
      user.save
      return user
    else
      return nil
    end
  end

  def create_ssg_admin_user(username, email, city_id, first_name, last_name, role, url)
    user = User.create_ssg_user(username, email, Digest::SHA1.hexdigest(Time.now().to_s), city_id)
    
    unless user.nil?
      user.role = role
      user.first_name = first_name
      user.last_name = last_name
      user.active = true
      user.save

      forgot_pass = create_random_reset_password(user)
      UserMailer.notify_admin_user_creation(user, forgot_pass.token, url).deliver
    end
  end

  def create_random_reset_password(user)
    forgot_pass = ForgotPassword.new
    forgot_pass.user = user
    forgot_pass.token = Digest::SHA1.hexdigest(Time.now().to_s + user.email)
    forgot_pass.save!
    return forgot_pass
  end

  def ssg_admin_update(params)
    user = User.find(params[:id])
    user.first_name = params[:user][:first_name]
    user.last_name = params[:user][:last_name]
    user.email = params[:user][:email]
    user.username = params[:user][:username]
    user.city_id = params[:user][:city_id]
    user.active = params[:user][:active]
    user.role = params[:user][:role]

    user.save!
  end

  def settings_update(params)
    self.first_name = params[:user][:first_name]
    self.last_name = params[:user][:last_name]
    self.city_id = params[:user][:city_id]
    self.locale = params[:user][:locale]
    self.website = params[:user][:website]
    self.description = params[:user][:description]

    if params[:image_count] && params[:image_count].to_i > 0
      last_image = params[:image_count].to_i - 1
      self.image_id = params["image_#{last_image}"]
    end

    if params[:password1] && params[:password2]
      if !params[:password1].strip.empty? && params[:password1].eql?(params[:password2])
        self.password_hash = Digest::SHA256.hexdigest(params[:password1])
      end
    end

    self.save
  end

end