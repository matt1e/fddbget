require "grape"
require "sqlite3"
require "sequel"
require "./scrape"
require "base64"

module Renderer
  extend self

  def to_erb(template)
    content = File.read(File.expand_path("#{template}.html.erb"))
    return ERB.new(content)
  end

  def bind_yield
    binding
  end

  def run(template, bind)
    to_erb(:layout).result(bind_yield { to_erb(template).result(bind) })
  end
end

module Db
  extend self

  def instance
    @instance ||= connect || init
  end

  def connect
    return unless File.exist?("db.sqlite")
    Sequel.connect("sqlite://db.sqlite")
  end

  def init
    db = Sequel.connect("sqlite://db.sqlite")
    db.create_table :food do
      primary_key :id
      Date :created_at
      String :category
      String :title, text: true
      String :brand, text: true
      String :url, text: true
      Numeric :nutrition_amount
      Numeric :nutrition_taken
      String :nutrition_unit
      Numeric :kalorien
      Numeric :protein
      Numeric :kohlenhydrate
      Numeric :davon_zucker
      Numeric :fett
    end
    return db
  end
end

class Fddb < Grape::API
  default_format :txt
  content_type :html, "text/html"

  get "/" do
    aggr = Db.instance[:food].group_and_count(:created_at, :category).
      select_append { sum(:kalorien).as("Kalorien") }.
      select_append { sum(:protein).as("Protein") }.
      select_append { sum(:kohlenhydrate).as("Kohlenhydrate") }.
      select_append { sum(:davon_zucker).as("Davon Zucker") }.
      select_append { sum(:fett).as("Fett") }.
      where { created_at > Date.today - 10 }.
      order(:created_at).reverse
    Renderer.run :index, binding
  end

  params do
    requires :created_at, type: String
  end
  get "/detail" do
    if declared(params)[:created_at] !~ /^\d{4}-\d{2}-\d{2}$/
      error = "Datum muss im Format yyyy-mm-dd sein"
      status 400
      Renderer.run :error, binding
    else
      args = declared(params)[:created_at].split("-").map(&:to_i)
      created_at = Date.new(*args)
      aggr = Db.instance[:food].
        where(created_at: created_at).
        order(:created_at).to_a
      Renderer.run :detail, binding
    end
  end

  params do
    requires :search_term, type: String
  end
  post "/search" do
    result = Scrape.search(declared(params)[:search_term]) do |food_url|
      Scrape.extract(food_url)
    end
    if result.empty?
      Renderer.run :not_found, binding
    else
      Renderer.run :search, binding
    end
  end

  params do
    requires :data, type: String
    requires :category, type: String
    requires :selected_weight, regexp: /other|(\d+([,\.]\d+)?)/
    requires :own_weight, type: String
    optional :create_at, type: String
  end
  post "/store" do
    if declared(params)[:selected_weight] == "other" &&
       declared(params)[:own_weight] !~ /^\d+([,\.]\d+)?$/
      error = "Gewichteingabe muss eine Zahl oder Kommazahl sein"
      status 400
      Renderer.run :error, binding
    elsif (declared(params)[:create_at]&.length || 0) > 0 &&
        declared(params)[:create_at] !~ /^\d{2}\.\d{2}\.\d{4}$/
      error = "Datum muss im Format dd.mm.yyyy sein"
      status 400
      Renderer.run :error, binding
    else
      data = JSON.parse(Base64.decode64(declared(params)[:data]),
        symbolize_names: true)
      weight = declared(params)[:selected_weight]
      weight = declared(params)[:own_weight] if weight == "other"
      weight = weight.sub(/,/, ".").to_f
      create_at = declared(params)[:create_at]
      if create_at.nil? || create_at.empty?
        create_at = Date.today
      else
        args = create_at.split(".").reverse.map(&:to_i)
        create_at = Date.new(*args)
      end
      calc = %i[
        kalorien
        protein
        kohlenhydrate
        davon_zucker
        fett
      ].reduce({}) do |acc, f|
        acc[f] = data[f].to_f / data[:naehrwerte][:amount].to_f * weight
        next acc
      end
      Db.instance[:food].insert({
        created_at: create_at,
        category: declared(params)[:category],
        title: data[:titel],
        brand: data[:marke],
        url: data[:url],
        nutrition_amount: data[:naehrwerte][:amount],
        nutrition_taken: weight,
        nutrition_unit: data[:naehrwerte][:unit]
      }.merge(calc))
      status 302
      header "location", "/"
    end
  end
end

run Fddb
