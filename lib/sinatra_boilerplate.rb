require 'sinatra/base'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'
require 'haml'
require 'sass'
require 'compass'
require 'uglifier'
require 'coffee_script'

# This Sinatra extension configures your app for serving Haml + HTML5,
# Sass + Compass, and CoffeeScript with concatenation and compression.
#
# The only requirement is defining your JavaScript assets:
#
#   set :js_assets, %w[zepto.js underscore.js app.coffee]
#
# Regular .js files should be directly under "public/" and .coffee
# files should be under "views/".
#
# Now use the `javascript_includes` helper to render SCRIPT tags.
#
# You must still handle serving individual .coffee and .sass files
# in your app, i.e. define the routes. However, in production mode
# all JavaScript assets will be served from "/all.js" which is a
# special resource that concatenates and compresses all files.
module SinatraBoilerplate
  module Helpers
    def javascript_assets
      settings.js_assets
    end

    def javascript_includes
      if settings.production? then %w[all.js]
      else javascript_assets.map {|f| File.basename(f, '.*') + '.js' }
      end.map {|a| %(<script src="/#{a}"></script>) }.join("\n")
    end

    def javascript_files
      javascript_assets.map do |name|
        dir = name.end_with?('.coffee') ? settings.views : settings.public
        File.join(dir, name)
      end
    end

    def render_javascript(files)
      Uglifier.new.compile files.map { |name|
        content = File.read name
        content = CoffeeScript.compile content if name.end_with?('.coffee')
        content
      }.join(";")
    end

    def file_mtime(name)
      name = File.join(settings.views, name) unless name.include? '/'
      File.mtime name
    end
  end

  def self.registered(app)
    app.helpers Helpers

    app.set :haml, format: :html5

    app.set :sass do
      Compass.configuration do |config|
        config.project_path = app.settings.root
        config.sass_dir = app.settings.views
      end

      Compass.sass_engine_options.merge \
        style: app.settings.production? ? :compressed : :nested,
        cache_location: File.join(ENV['TMPDIR'], 'sass-cache')
    end

    # poor man's Sprockets
    app.get "/all.js" do
      content_type 'application/javascript'
      files = javascript_files

      expires 1.day
      last_modified files.map {|f| file_mtime(f) }.max

      render_javascript files
    end
  end
end

Sinatra.register SinatraBoilerplate
