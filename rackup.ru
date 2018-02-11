require "grape"
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
    p result
    if result.empty?
      Renderer.run :not_found, binding
    else
      Renderer.run :search, binding
    end
  end
end

run Fddb
