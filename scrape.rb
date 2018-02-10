require "parser_girl"
require "net/http"
require "cgi"
require "htmlentities"

module Scrape
  extend self

  SEARCH_URL = "http://fddb.info/db/de/suche/?udd=0&cat=site-de&search=%{term}"

  def search(needle)
    url = SEARCH_URL % {term: CGI.escape(needle)}
    body = Net::HTTP.get(URI(url))
    pg = ParserGirl.new(body)
    food = pg.find("tr").reduce(nil) do |acc, elem|
      next acc if acc
      cols = elem.find("td")
      if cols.first.content.strip == "Beliebt"
        next cols.to_a[1].find("a").to_h.first[:href]
      end
    end
    return food ? yield(food) : {status: "error", reason: "no food found"}
  end

  def decode(str)
    str.force_encoding("iso-8859-1").encode("UTF-8")
  end

  def extract(food_url)
    body = Net::HTTP.get(URI(food_url))
    pg = ParserGirl.new(body)
    data = pg.find("div").reduce({}) do |acc, div|
      next acc unless div.to_h[:class] == "standardcontent"
      next acc.merge(
        title: title(pg),
        naehrwerte_100g: nutrition(div),
        options: options(pg)
      ).merge(details(div))
    end
    return data
  end

  def title(container)
    return container.find("h1").reduce(nil) do |acc, h1|
      next acc unless h1.to_h[:id] == "fddb-headline1"
      next HTMLEntities.new.decode(h1.content)
    end
  end

  def nutrition(container)
    return container.find("h2").reduce(nil) do |acc, h2|
      next acc unless decode(h2.content).include?("Nährwerte")
      next h2.content.match(/(\d+)/).captures.first.to_i
    end
  end

  def details(container)
    fields = ["Kalorien", "Protein", "Kohlenhydrate", "davon Zucker", "Fett"]
    return fields.reduce({}) do |acc, field|
      acc[field.downcase.gsub(" ", "_")] = detail(container, field)
      next acc
    end
  end

  def detail(container, field)
    return container.find("div").reduce(nil) do |acc, div|
      name = div.find("div").first&.find("a")&.content
      if name.nil? || name.empty?
        name = div.find("div").first&.find("span")&.content
      end
      next acc unless name == field
      value = div.find("div").content.last
      next value.match(/([\d,]+)/).captures.first.sub(/,/, ".").to_f
    end
  end

  def options(container)
    return container.find("a").reduce([]) do |acc, a|
      next acc unless a.to_h[:class] == "servb"
      name, weight = a.content.match(/^(.*) \(([\d,]+)\s+g\)$/).captures
      next acc << {
        name: HTMLEntities.new.decode(name),
        weight: weight.sub(/,/, ".").to_f
      }
    end
  end
end

p(Scrape.search("eiernudeln") do |food_url|
  Scrape.extract(food_url)
end)
