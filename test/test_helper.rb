require 'minitest/spec'
require 'minitest/unit'

MiniTest::Unit.autorun

def read_fixture(name)
  File.read(File.expand_path("../fixtures/#{name}", __FILE__))
end
