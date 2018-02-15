require "parser_girl"
require "net/http"
require "cgi"
require "htmlentities"

module Scrape
  extend self

  SEARCH_URL = "http://fddb.info/db/de/suche/?udd=0&cat=site-de&search=%{term}"

  def search(needle)
    url = SEARCH_URL % {term: CGI.escape(needle.encode("iso-8859-1"))}
    resp = Net::HTTP.get_response(URI(url))
    if resp.is_a?(Net::HTTPSuccess)
      pg = ParserGirl.new(resp.body)
      food = pg.find("tr").reduce(nil) do |acc, elem|
        next acc if acc
        cols = elem.find("td")
        match = ["Sehr beliebt", "Beliebt", "Normal"].any? do |e|
          cols.first.content.strip == e
        end
        next cols.to_a[1].find("a").to_h.first[:href] if match
      end
    elsif resp.is_a?(Net::HTTPRedirection)
      food = resp["location"]
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
        titel: title(pg),
        marke: brand(pg),
        url: food_url,
        naehrwerte: nutrition(div),
        options: options(pg)
      ).merge(details(div))
    end
    return data
  end

  def title(container)
    return container.find("h1").reduce(nil) do |acc, h1|
      next acc unless h1.to_h[:id] == "fddb-headline1"
      next HTMLEntities.new.decode(decode(h1.content))
    end
  end

  def brand(container)
    return container.find("h2").reduce(nil) do |acc, h1|
      next acc unless h1.to_h[:id] == "fddb-headline2"
      next HTMLEntities.new.decode(decode(h1.find("a").content.first))
    end
  end

  def nutrition(container)
    return container.find("h2").reduce(nil) do |acc, h2|
      next acc unless decode(h2.content).include?("Nährwerte")
      amount, unit = h2.content.match(/(\d+) ([a-z]+)/).captures
      next {amount: amount.to_i, unit: unit}
    end
  end

  def details(container)
    fields = ["Kalorien", "Protein", "Kohlenhydrate", "davon Zucker", "Fett"]
    return fields.reduce({}) do |acc, field|
      acc[field.downcase.gsub(" ", "_").to_sym] = detail(container, field)
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
      name, weight = a.content.match(/^(.*) \(([\d,]+)\s+\S+\)$/)&.captures
      next acc if name.nil?
      next acc << {
        name: HTMLEntities.new.decode(name),
        weight: weight.sub(/,/, ".").to_f
      }
    end
  end
end
