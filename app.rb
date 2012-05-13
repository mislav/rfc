# encoding: utf-8
require 'sinatra'
require_relative 'lib/sinatra_boilerplate'
require_relative 'rfc'

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
  ENV['DATABASE_URL'] ||= 'postgres://localhost/rfc'
end

configure :production do
  require 'rack/cache'
  use Rack::Cache,
    :verbose     => true,
    :metastore   => "file:#{ENV['TMPDIR']}/rack/meta",
    :entitystore => "file:#{ENV['TMPDIR']}/rack/body"
end

require 'dm-core'

configure :development do
  DataMapper::Logger.new($stderr, :debug)
end

configure do
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end

require_relative 'models'

get "/" do
  cache_control :public
  last_modified File.mtime('views/index.erb')
  erb :index, {}, title: "Pretty RFCs"
end

get "/search" do
  @query = params[:q]
  @results = RfcEntry.search_raw @query, page: params[:page], limit: 50
  erb :search, {}, title: "RFC search"
end

get "/oauth" do
  expires 3600, :public
  doc = RFC::Document.new File.open('draft-ietf-oauth-v2-25.xml')
  html = RFC::TemplateHelpers.render doc
  render :str, html, {layout_engine: :erb}, title: "OAuth 2.0"
end
