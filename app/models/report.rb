# -*- encoding : utf-8 -*-
class Report
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :bill

  field :date, :type => DateTime
  field :step, :type => String
  field :stage, :type => String
  field :link, :type => String
end
