require 'nokogiri'
doc = Nokogiri::HTML ARGF

doc.search('article, section, figure, figcaption, hgroup, mark').reverse.each do |elem|
  type = elem.name
  type = 'caption' if type == 'figcaption'
  elem.name = type == 'mark' ? 'span' : 'div'

  classnames = elem['class'].to_s.lstrip.split(/\s+/)
  unless classnames.include? type
    classnames << type 
    elem['class'] = classnames.join(' ')
  end
end

puts doc
