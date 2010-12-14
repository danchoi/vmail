require 'liquid'
require 'rdiscount'
markdown = RDiscount.new File.read("page.markdown")

template = File.read("vmail-template.html")
out = Liquid::Template.parse(template).render 'content' => markdown.to_html, 'timestamp' => Time.now.to_i
puts out
