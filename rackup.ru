require "grape"
require "sqlite3"
require "sequel"
require "./scrape"

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
    Renderer.run :index, binding
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
end

run Fddb
