require "erb"
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
    db.create_table :cache do
      primary_key :id
      String :title, text: true
      String :data, text: true
    end
    return db
  end
end

class Fddb < Grape::API
  default_format :txt
  content_type :html, "text/html"

  params do
    optional :all, type: String
  end
  get "/" do
    aggr = Db.instance[:food].group_and_count(:created_at, :category).
      select_append { sum(:kalorien).as("Kalorien") }.
      select_append { sum(:protein).as("Protein") }.
      select_append { sum(:kohlenhydrate).as("Kohlenhydrate") }.
      select_append { sum(:davon_zucker).as("Davon Zucker") }.
      select_append { sum(:fett).as("Fett") }.
      order(:created_at).reverse
    unless declared(params)[:all] == "true"
      aggr = aggr.where { created_at > Date.today - 10 }
    end
    categories = {
      "Kalorien" => 0.0,
      "Gruppe 1 Getreide" => 0.0,
      "Gruppe 2 Milch" => 0.0,
      "Gruppe 3 Fleisch" => 0.0,
      "Gruppe 4 Gemüse" => 0.0,
      "Gruppe 5 Obst" => 0.0,
      "Gruppe 6 Fett" => 0.0,
      "Gruppe 7 Extras" => 0.0
    }
    aggr = aggr.reduce({}) do |acc, row|
      acc[row[:created_at]] ||= categories.dup
      acc[row[:created_at]]["Kalorien"] += row[:Kalorien]
      acc[row[:created_at]][row[:category]] = row[:Kohlenhydrate] / 25.0 +
        row["Davon Zucker".to_sym] / 25.0 + row[:Fett] / 10.0 +
        row[:Protein] / 15.0
      next acc
    end
    cached_names = Db.instance[:cache].select(:title).map { |r| r[:title] }
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
    if declared(params)[:search_term].include?(" -cached")
      result = JSON.parse(Base64.decode64(Db.instance[:cache].
        first(
          title: declared(params)[:search_term].sub(/ -cached/, "")
        )[:data]), symbolize_names: true)
    else
      result = Scrape.search(declared(params)[:search_term]) do |food_url|
        Scrape.extract(food_url)
      end
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
    elsif declared(params)[:own_weight].length > 0 &&
          declared(params)[:selected_weight] != "other"
      error = "Entscheide dich. Eigenes Gewicht ODER Voreinstellung!"
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
      insert = {
        created_at: create_at,
        category: declared(params)[:category],
        title: data[:titel],
        brand: data[:marke],
        url: data[:url],
        nutrition_amount: data[:naehrwerte][:amount],
        nutrition_taken: weight,
        nutrition_unit: data[:naehrwerte][:unit]
      }
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
      args =
        if insert[:category] == "Aufsplitten"
          fields = {
            protein: "Gruppe 3 Fleisch",
            kohlenhydrate: "Gruppe 1 Getreide",
            davon_zucker: "Gruppe 7 Extras",
            fett: "Gruppe 6 Fett"
          }
          sum_weight = fields.keys.reduce(0.0) { |a, f| a + calc[f].to_f }
          cal_split = fields.keys.reduce({}) do |acc, f|
            acc[f] = calc[:kalorien].to_f * calc[f].to_f / sum_weight
            next acc
          end
          fields.keys.each { |f| insert[f] = 0.0 }
          fields.map do |f, c|
            insert.dup.merge(category: c, kalorien: cal_split[f], f => calc[f])
          end
        else
          [insert.merge(calc)]
        end
      Db.instance[:food].multi_insert(args)
      if Db.instance[:cache].first(title: data[:titel]).nil?
        Db.instance[:cache].insert(title: data[:titel],
          data: declared(params)[:data])
      end
      status 302
      header "location", "/"
    end
  end

  params do
    requires :id, type: Integer
  end
  post "food/:id/delete" do
    food = Db.instance[:food].where(id: declared(params)[:id])
    created_at = food.first[:created_at]
    food.delete
    status 302
    header "location", "/detail?created_at=#{created_at}"
  end
end

if ENV["BASIC_USER"]
  use Rack::Auth::Basic, ENV["BASIC_USER"] do |username, password|
      Rack::Utils.secure_compare(ENV["BASIC_PASS"], password)
  end
end

use Rack::Static, root: "public",
  urls: Dir["public/*"].map { |f| "/#{f.sub(/^public\//, "")}" }

run Fddb
