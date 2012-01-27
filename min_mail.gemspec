# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "vmail/version"

Gem::Specification.new do |s|
  s.name        = "edmail"
  s.version     = MinMail::VERSION
  s.platform    = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.0'

  s.authors     = ["Daniel Choi"]
  s.email       = ["dhchoi@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{min_mail}
  s.description = %q{A mini command line imap email client}

  s.rubyforge_project = "vmail_cli"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'mail', '>= 2.2.12'
  s.add_dependency 'highline', '>= 1.6.1'
end
