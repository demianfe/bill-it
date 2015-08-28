# -*- encoding : utf-8 -*-
class Count
  include Mongoid::Document

  embedded_in :vote_event

  field :option, type: String
  field :value, type: Integer
end
