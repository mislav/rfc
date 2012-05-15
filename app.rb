# encoding: utf-8
require 'sinatra'
require_relative 'lib/sinatra_boilerplate'

bootstrap_root = File.expand_path('bootstrap', settings.root)

set :sass do
  options = {
    style: settings.production? ? :compressed : :nested,
    load_paths: ['.', File.join(bootstrap_root, 'lib')]
  }
  options[:cache_location] = File.join(ENV['TMPDIR'], 'sass-cache') if ENV['TMPDIR']
  options
end

use Rack::Static, urls: %w[/img], root: bootstrap_root

set :js_assets, %w[zepto.js app.coffee]

configure :development do
  set :logging, false
  ENV['DATABASE_URL'] ||= 'postgres://localhost/rfc'
end

configure :production do
  require 'rack/cache'
  use Rack::Cache,
    verbose:     true,
    metastore:   'memcached://localhost/meta',
    entitystore: 'memcached://localhost/body?compress=true'
end

require 'dm-core'

configure :development do
  DataMapper::Logger.new($stderr, :debug)
end

configure do
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end

require_relative 'models'

configure do
  DataMapper.finalize
  DataMapper::Model.raise_on_save_failure = true
  RfcFetcher.download_dir = File.expand_path('../tmp/xml', __FILE__)
end

helpers do
  def display_document_id doc
    doc.id.sub(/(\d+)/, ' \1')
  end

  def display_abstract text
    text.sub(/\[STANDARDS[ -]{1,2}TRA?CK\]/, '') if text
  end

  def search_path options = {}
    get_params = request.GET.merge('page' => options[:page])
    url '/search?' + Rack::Utils.build_query(get_params), false
  end

  def rfc_path doc
    doc_id = String === doc ? doc : doc.id
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
  page_title "Pretty RFC"
end

error 404 do
  erb :not_found
end

get "/" do
  cache_control :public
  last_modified File.mtime('views/index.erb')
  erb :index
end

get "/search" do
  expires 5 * 60, :public
  @query = params[:q]
  @limit = 50
  @results = RfcDocument.search @query, page: params[:page], limit: @limit
  erb :search
end

get %r{^/ (?<doc_id> [a-z]* -? \d+) $}ix do
  @rfc = RfcDocument.fetch(params[:doc_id]) { not_found }
  redirect to(@rfc.id) unless request.path == "/#{@rfc.id}"

  cache_control :public
  last_modified @rfc.last_modified

  @rfc.make_pretty ->(xref) { rfc_path(xref) if xref =~ /^RFC\d+$/ }
  erb :show
end
