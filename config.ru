require 'rubygems'
require 'bundler'

Bundler.setup
$LOAD_PATH.unshift ENV['APP_ROOT'] || File.expand_path('..', __FILE__)
$LOAD_PATH.unshift File.join($LOAD_PATH.first, 'lib')

Encoding.default_external = 'utf-8'

# require 'ruby-debug' if ENV['RACK_ENV'] == 'development'

require 'app'
run Sinatra::Application
