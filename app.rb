# encoding: utf-8
require 'sinatra'
require 'sinatra_boilerplate'

set :js_assets, %w[zepto.js underscore.js app.coffee]

configure :development do
  set :logging, false
end

get "/" do
  haml :index
end

get "/style.css" do
  expires 1.day
  last_modified file_mtime('style.sass')
  sass :style
end

get "/app.js" do
  expires 5.minutes
  last_modified file_mtime('app.coffee')
  coffee :app
end
