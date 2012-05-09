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
  ENV['DATABASE_URL'] ||= 'postgres://localhost/rfc'
end

require 'dm-migrations'
require_relative 'searchable'

configure :development do
  DataMapper::Logger.new($stderr, :debug)
end

configure do
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end

class RfcEntry
  include DataMapper::Resource
  extend Searchable

  property :document_id, String, length: 10,   key: true
  property :title,       String, length: 255
  property :abstract,    Text,   length: 2200
  property :keywords,    Text,   length: 500

  def keywords=(value)
    if Array === value
      super(value.empty?? nil : value.join(', '))
    else
      super
    end
  end

  searchable [:title, :abstract, :keywords]
end

get "/" do
  cache_control :public
  last_modified File.mtime('views/index.erb')
  erb :index, {}, title: "Pretty RFCs"
end

get "/search" do
  @query = params[:q]
  @results = RfcEntry.search @query, limit: 50
  erb :search, {}, title: "RFC search"
end

get "/oauth" do
  expires 3600, :public
  doc = RFC::Document.new File.open('draft-ietf-oauth-v2-25.xml')
  html = RFC::TemplateHelpers.render doc
  render :str, html, {layout_engine: :erb}, title: "OAuth 2.0"
end
