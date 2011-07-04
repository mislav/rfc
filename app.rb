# encoding: utf-8
require 'sinatra'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'haml'
require 'sass'
require 'compass'
require 'uglifier'
require 'coffee_script'

Compass.configuration do |config|
  config.project_path = settings.root
  config.sass_dir = 'views'
end

set :haml, format: :html5

set :sass do
  Compass.sass_engine_options.merge style: settings.production? ? :compressed : :nested,
    cache_location: File.join(ENV['TMPDIR'], 'sass-cache')
end

configure :development do
  set :logging, false
end

JS_ASSETS = %w[zepto.js underscore.js app.coffee]

helpers do
  def javascript_includes
    assets = settings.production? ? 'all.js' : JS_ASSETS.map {|f| File.basename(f, '.*') + '.js' }
    assets.map {|a| %(<script src="/#{a}"></script>) }.join("\n")
  end

  def file_mtime(name)
    name = File.join(settings.views, name) unless name.include? '/'
    File.mtime name
  end
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

# poor man's Sprockets
get "/all.js" do
  content_type 'application/javascript'

  files = JS_ASSETS.map do |name|
    dir = (".coffee" == File.extname(name)) ? settings.views : settings.public
    File.join(dir, name)
  end

  expires 1.day
  last_modified files.map {|f| file_mtime(f) }.max

  contents = files.map do |name|
    content = File.read name
    content = CoffeeScript.compile content if ".coffee" == File.extname(name)
    content
  end
  Uglifier.new.compile contents.join(";")
end
