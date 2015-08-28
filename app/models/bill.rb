# -*- encoding : utf-8 -*-
class Bill
  require 'open-uri'
  include Mongoid::Document
  include Mongoid::Timestamps

  validates_presence_of :uid
  validates_uniqueness_of :uid

  before_save :arrayify, :standardize_tags, :set_current_priority
  after_save :index!

  has_many :paperworks, autosave: true, class_name: "Paperwork"
  has_many :priorities, autosave: true, class_name: "Priority"
  has_many :reports, autosave: true, class_name: "Report"
  has_many :documents, autosave: true, class_name: "Document"
  has_many :directives, autosave: true, class_name: "Directive"
  has_many :remarks, autosave: true, class_name: "Remark"
  has_many :motions, autosave: true, class_name: "Motion"
  embeds_many :revisions
  
  field :uid, type: String
  field :title, type: String
  field :abstract, type: String
  field :creation_date, type: Time
  field :source, type: String
  field :initial_chamber, type: String
  field :stage, type: String
  field :sub_stage, type: String
  field :status, type: String
  field :resulting_document, type: String
  field :merged_bills, type: Array
  field :subject_areas, type: Array
  field :authors, type: Array
  field :publish_date, type: Time
  field :tags, type: Array
  field :bill_draft_link, type: String
  field :current_priority, type: String
 
  scope :urgent, where(:current_priority.in => ["Discusión inmediata", "Suma", "Simple"])

  include Sunspot::Mongoid2
  searchable do
    text :uid
    text :short_uid
    text :title
    text :abstract
    time :creation_date
    text :source
    text :initial_chamber
    text :current_priority
    text :stage
    text :sub_stage
    text :status
    text :subject_areas
    text :authors
    time :publish_date
    text :tags
    time :updated_at
    #attachment type has to be a uri (local or remote)
    #if it's a string it will not get indexed
    attachment :bill_draft
    attachment :law_text
  end

  def get_current_priority
    return "Sin urgencia" if self.priorities.blank?
    all_priorities = self.priorities.in_memory.blank? ? self.priorities : self.priorities.in_memory
    latest_priority = all_priorities.reject{|x| x.entry_date.blank?}.sort{ |x,y| y.entry_date <=> x.entry_date }.first
    return "Sin urgencia" if latest_priority.type == "Sin urgencia" or latest_priority.entry_date > Date.today
    
    days_in_force = case latest_priority.type
      when "Discusión inmediata"
        6
      when "Suma"
        15
      when "Simple"
        30
      else
        return "Sin urgencia"
    end

    if (latest_priority.entry_date + days_in_force.days) >= Date.today
      latest_priority.type
    else
      "Sin urgencia"
    end
  end

  def set_current_priority
    self.current_priority = get_current_priority
  end

  def law_id
    self.resulting_document.gsub(/Ley[^\d]*(\d+)\.?(\d*)/, '\1\2') if resulting_document =~ /Ley[^\d]*(\d+)\.?(\d*)/
  end

  def law_xml_link
    if !self.law_id.blank?
      "http://www.leychile.cl/Consulta/obtxml?opt=7&idLey=" + law_id
    end
  end

  def law_web_link
    if !self.law_id.blank?
      "http://www.leychile.cl/Navegar?idLey=" + law_id
    end
  end

  def to_param
    uid
  end

  def arrayify
    ["subject_areas", "authors", "tags"].each do |field|
      if field.class == String
        field = field.split(/;|\|/)
      end
    end
  end
    

  def standardize_tags
    if self.tags.class == Array
      self.tags.map! do |tag|
        tag = I18n.transliterate(tag, locale: :transliterate_special).downcase.strip
      end
    end
  end

  def short_uid
    self.uid.split("-")[0]
  end

  # The two methods below only exist so the query fields have nicer names
  def bill_draft
    self.bill_draft_link
  end

  def law_text
    law_xml_link
  end

  def icon
    if ! self.status.blank?
      case self.status.strip
      when "Archivado"
        return 'filed.png'
      when "Publicado"
        return 'published.png'
      when "En tramitación"
        return 'paperwork.png' #icono pendiente 
      when "Rechazado"
        return 'rejected.png' 
      when "Retirado"
        return 'discarded.png' 
      else
        return 'paperwork.png'
      end
    end
    return 'paperwork.png'
  end

  def self.update_priority
    Bill.urgent.each do |bill|
      bill.save
    end
  end
end
