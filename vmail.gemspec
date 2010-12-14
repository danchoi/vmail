# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "vmail/version"

Gem::Specification.new do |s|
  s.name        = "vmail"
  s.version     = Vmail::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Daniel Choi"]
  s.email       = ["dhchoi@gmail.com"]
  s.homepage    = "http://danielchoi.com/software/vmail.html"
  s.summary     = %q{A Vim interface to Gmail}
  s.description = %q{Manage your email with Vim}

  s.rubyforge_project = "vmail"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'mail', '>= 2.2.12'
  s.add_dependency 'highline', '>= 1.6.1'
end
