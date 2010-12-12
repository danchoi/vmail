# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "vmail/version"

Gem::Specification.new do |s|
  s.name        = "vmail"
  s.version     = Vmail::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Daniel Choi"]
  s.email       = ["dhchoi@gmail.com"]
  s.homepage    = "http://rubygems.org/gems/vmail"
  s.summary     = %q{A Vim interface to Gmail}
  s.description = %q{Manage your email with Vim}

  s.rubyforge_project = "vmail"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'mail'
end
