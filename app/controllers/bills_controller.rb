# -*- encoding : utf-8 -*-
require 'billit_representers/models/bill'
require 'billit_representers/models/bill_page'
require 'billit_representers/representers/bill_representer'
require 'billit_representers/representers/bill_basic_representer'
require 'billit_representers/representers/bill_page_representer'
Dir['./app/models/billit/*'].each { |model| require model }

class BillsController < ApplicationController
  include Roar::Rails::ControllerAdditions
  # represents :json, :entity => Billit::BillRepresenter, :collection => Billit::BillPageRepresenter
  respond_to :json, :xml, :html
  # json /bills
  # GET /bills.json
  # def index
  #   # require 'will_paginate/array'
  #   # @bills = Bill.all.to_a
  #   # @bills.extend(Billit::BillPageRepresenter)
  #   # respond_with @bills.to_json(params), represent_with: Billit::BillPageRepresenter
  #   search
  # end

  # GET /id/feed
  def feed
    @bill = Bill.find_by(uid: params[:id])

    # this will be our Feed's update timestamp
    @updated_at = @bill.updated_at unless @bill.nil?
    
    render text: @updated_at
  end

  # GET /bills/1.json
  def show
    @condition_bill_header = true
    if params[:fields]
      fields = params[:fields].split(',')
      @bill = Bill.only(fields).find_by(uid: params[:id])
      # render json: @bill.to_json(only: fields)
      respond_with @bill, :callback => params['callback'], :represent_with => Billit::BillBasicRepresenter
    else
      @bill = Bill.find_by(uid: params[:id])
      if @bill.nil?
        render text: "", :status => 404
      else
        respond_with @bill, :callback => params['callback'], :represent_with => Billit::BillRepresenter
      end
    end
  end

  # GET /bills/search.json?q=search_string
  def search
    require 'will_paginate/array'

    # Sunspot.remove_all(Bill)   # descomentar para reindexar,
    # Sunspot.index!(Bill.all)   # en caso de cambio en modelo
    search = search_for(params)
    @bills = search.results
    if params[:fields]
      fields = params[:fields].split(',')
      @bills.map! {|bill| Bill.only(fields).find_by(uid: bill.uid)}
      @bills.extend(Billit::BillPageRepresenter)
      respond_with @bills.to_json(params), :callback => params['callback'], represent_with: Billit::BillPageRepresenter
    else
      @bills.extend(Billit::BillPageRepresenter)
      @bills_query = Billit::BillPage.new.from_json(@bills.to_json(params))
      respond_with @bills.to_json(params), :callback => params['callback'], represent_with: Billit::BillPageRepresenter
    end
  end
  alias index search

  # GET /bills/new
  # GET /bills/new.json
  def new
    @bill = Bill.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @bill }
    end
  end

  # GET /bills/1/edit
  def edit
    @bill = Bill.find_by(uid: params[:id])
  end

  # POST /bills
  # POST /bills.json
  def create
    @bill = Bill.new.extend(Billit::BillRepresenter)
    begin
      @bill.from_json(request.body.read)
    rescue MultiJson::LoadError
      params[:bill].keys.each do |key|
        @bill.send(key.to_s + "=", params[:bill][key])
      end
    end
    @bill.save
    begin
      puts "indexing" 
      Sunspot.index!(@bill)

    rescue
      puts "#{$!}"
      puts "unindexed bill: " + @bill.uid
    end
    respond_with @bill, :represent_with => Billit::BillRepresenter
  end

  # PUT /bills/1
  # PUT /bills/1.json
  def update
    @bill = Bill.find_by(uid:params[:id]).extend(Billit::BillRepresenter)
    # @bill = Bill.find_by(uid:params[:id])
    if params[:tags]
      @bill.tags = params[:tags]
      @bill.save
    else
      begin
        @bill.from_json(request.body.read)
      rescue MultiJson::LoadError
        params[:bill].keys.each do |key|
          # if key == 'tags'
          #   @bill.tags = params[:bill][:tags].split(/,|;|\|/)
          # else
            @bill.send(key.to_s + "=", params[:bill][key])
          # end
        end
      end
      @bill.save
      begin
        Sunspot.index!(@bill)
      rescue
        puts "#{$!}"
        puts "unindexed bill: " + @bill.uid
      end
    end
    respond_with @bill, :represent_with => Billit::BillRepresenter
  end

  # DELETE /bills/1
  # DELETE /bills/1.json
  def destroy
    @bill = Bill.find(params[:id])
    @bill.destroy

    respond_to do |format|
      format.html { redirect_to bills_url }
      format.json { head :no_content }
    end
  end

  def filter_conditions(conditions)
    @mongoid_attribute_names = ["_id", "created_at"] #FIX should probably have a greater scope
    @search_attribute_names = ["q", "bill_id", "law_text", "bill_draft"]
    @range_field_types = [Time]
    @range_modifier_min = "_min"
    @range_modifier_max = "_max"

    bill_range_fields = Bill.fields.dup
    @range_field_types.each do |type|
      bill_range_fields.reject! {|field_name, metadata| metadata.options[:type]!= type}
    end
    bill_range_attributes = bill_range_fields.keys

    bill_public_attributes = Bill.attribute_names - @mongoid_attribute_names

    equivalence_attributes = bill_public_attributes + @search_attribute_names
    range_attributes_min = bill_range_attributes.map {|attribute| attribute + @range_modifier_min}
    range_attributes_max = bill_range_attributes.map {|attribute| attribute + @range_modifier_max}

    filtered_conditions = {}
    equivalence_conditions = {}
    disjunction_conditions = {}
    range_conditions_min = {}
    range_conditions_max = {}
    conditions.each do |key, value|
      next if value.nil?() || value == ""
      if equivalence_attributes.include?(key)
        if value =~ /\|/
          disjunction_conditions[key] = value
        else
          equivalence_conditions[key] = value
        end
      elsif range_attributes_min.include?(key)
        range_conditions_min[key.gsub(@range_modifier_min, "")] = value
      elsif range_attributes_max.include?(key)
        range_conditions_max[key.gsub(@range_modifier_max, "")] = value
      end
    end

    return {equivalence_conditions: equivalence_conditions, disjunction_conditions: disjunction_conditions,\
      range_conditions_min: range_conditions_min, range_conditions_max: range_conditions_max}
  end

  def search_for(conditions)
    filtered_conditions = filter_conditions(conditions)
    puts conditions
    search = Sunspot.search(Bill) do
      # FIX the equivalence conditions settings should be in a conf file
      # search over all fields
      if filtered_conditions[:equivalence_conditions].key?("q")
        fulltext filtered_conditions[:equivalence_conditions]["q"] do
          boost_fields :tags => 10.0
          boost_fields :subject_areas => 7.0
          boost_fields :title => 4.0
          boost_fields :abstract => 2.0
        end
        filtered_conditions[:equivalence_conditions].delete("q")
      end
      # search over bill identifiers, both uid and short uid
      if filtered_conditions[:equivalence_conditions].key?("bill_id")
        text_fields do
          any_of do
            with(:uid, filtered_conditions[:equivalence_conditions]["bill_id"])
            with(:short_uid, filtered_conditions[:equivalence_conditions]["bill_id"])
          end
        end
        filtered_conditions[:equivalence_conditions].delete("bill_id")
      end
      # search over specific fields
      filtered_conditions[:equivalence_conditions].each do |key, value|
        fulltext value do
          fields key
        end
      end
      #search over specific fields that come with |
      text_fields do
        all_of do
          filtered_conditions[:disjunction_conditions].each do |key, value|
            any_of do
              value.split("|").each do |term|
                with(key, term)
              end
            end
          end
        end
      end

      all_of do
        #range_conditions_min might be asdf_min instead of asdf
        filtered_conditions[:range_conditions_min].each do |key, value|
          with(key).greater_than(value)
        end
        filtered_conditions[:range_conditions_max].each do |key, value|
          with(key).less_than(value)
        end
      end

      paginate page:conditions[:page], per_page:conditions[:per_page]
      order_by(:creation_date, :desc)
      search
    end
  end

  def last_update
    @date = Bill.max(:updated_at).strftime("%d/%m/%Y")
    render :text => @date
  end

end
