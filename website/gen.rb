require 'liquid'
require 'rdiscount'

top = RDiscount.new(File.read("top.markdown")).to_html

readme = File.expand_path("../../README.markdown", __FILE__)

raise "no README" unless File.size?(readme)

middle_markdown = File.read(readme).split(/^\s*$/)

middle_markdown = middle_markdown[2..-1].join("\n\n")

middle = RDiscount.new(middle_markdown).to_html

bottom = RDiscount.new(File.read("bottom.markdown")).to_html

content = [top, middle, bottom].join("\n\n")

template = File.read("vmail-template.html")
out = Liquid::Template.parse(template).render 'content' => content, 'timestamp' => Time.now.to_i
puts out
