class Category < ActiveRecord::Base

  include SoftDelete

  has_many  :issues
  
  has_many :children, :class_name => "Category", :foreign_key => "parent_id"
  belongs_to :parent, :class_name => "Category"

  DEFAULT_ICON = 'default.png'

  default_scope where(:deleted => false)
  #
  # Returns true if created, false if edited
  #
  def self.create_or_edit(params)
    require 'pp'
    pp params
    category = (category_id = params[:category_id]).empty? ? Category.new : Category.find(category_id)
    category.name = params[:category_name]
    category.description = params[:description]
    category.parent  = params[:parent_category_id] && params[:parent_category_id] != '0' ? Category.find(params[:parent_category_id]) : nil
    category.color = params[:color].gsub('#','')
    category.icon = category.icon || DEFAULT_ICON
    category.save!

    return category_id.empty?
  end

  def self.subcategories_ids(parent_id)
    Category.select(:id).where(:parent_id => parent_id).pluck(:id)
  end
end