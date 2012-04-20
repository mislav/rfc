# encoding: utf-8
require 'sinatra'
require 'sinatra_boilerplate'
require 'rfc'

set :sass do
  options = {
    style: settings.production? ? :compressed : :nested,
    load_paths: ['.', File.expand_path('bootstrap/lib', settings.root)]
  }
  options[:cache_location] = File.join(ENV['TMPDIR'], 'sass-cache') if ENV['TMPDIR']
  options
end

set :js_assets, %w[zepto.js app.coffee]

configure :development do
  set :logging, false
end

get "/" do
  expires 500, :public
  erb :index, {}, title: "Pretty RFCs"
end

get "/oauth" do
  expires 500, :public
  doc = RFC::Document.new File.open('draft-ietf-oauth-v2-25.xml')
  html = RFC::TemplateHelpers.render doc
  render :str, html, {layout_engine: :erb}, title: "OAuth 2.0"
end
