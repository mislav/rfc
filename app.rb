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

helpers do
  def display_document_id doc_id
    doc_id = doc_id.document_id if doc_id.respond_to? :document_id
    doc_id.sub(/(\d+)/, ' \1')
  end

  def display_abstract text
    text.sub(/\[STANDARDS[ -]{1,2}TRA?CK\]/, '') if text
  end

  def search_path options = {}
    get_params = request.GET.merge('page' => options[:page])
    url '/search?' + Rack::Utils.build_query(get_params), false
  end

  def rfc_path doc_id
    doc_id = doc_id.document_id if doc_id.respond_to? :document_id
    url doc_id, false
  end

  def home_path
    url '/'
  end

  def page_title title = nil
    if title
      @page_title = title
    else
      @page_title
    end
  end
end

before do
  page_title "Pretty RFCs"
end

get "/" do
  cache_control :public
  last_modified File.mtime('views/index.erb')
  erb :index
end

get "/search" do
  @query = params[:q]
  @limit = 50
  @results = RfcEntry.search_raw @query, page: params[:page], limit: @limit
  erb :search
end

get "/oauth" do
  expires 3600, :public
  doc = RFC::Document.new File.open('draft-ietf-oauth-v2-25.xml')
  html = RFC::TemplateHelpers.render doc
  render :str, html, {layout_engine: :erb}, title: "OAuth 2.0"
end
