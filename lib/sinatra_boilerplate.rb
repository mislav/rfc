require 'sinatra/base'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/time/acts_like'

# This Sinatra extension configures your app for serving Haml + HTML5,
# Sass + Compass, and CoffeeScript with concatenation and compression.
#
# The only requirement is defining your JavaScript assets:
#
#   set :js_assets, %w[zepto.js underscore.js app.coffee]
#
# Regular .js files must be under "public/", and .coffee under "views/".
#
# Now use the `javascript_includes` helper to render SCRIPT tags.
#
# The provided middleware will serve individual .coffee and .s[ac]ss files.
# In production mode all JavaScript assets will be served from "/all.js"
# which is a special resource that concatenates and compresses all files.
module SinatraBoilerplate
  # poor man's Sprockets
  class Middleware < Struct.new(:app, :settings)
    DEFAULT_EXPIRES = 60*60*24*7 # a week
    JS_MIME = 'application/javascript'

    attr_reader :expires_in

    def initialize(app, settings, options = {})
      super(app, settings)
      @expires_in = options.fetch(:expires_in, DEFAULT_EXPIRES).to_i
    end

    def template_path(path)
      File.join(settings.views, path)
    end

    def call(env)
      if env['PATH_INFO'] =~ /\.(js|css)$/
        path, ext = $`, $1

        # /css/style.css -> views/css/style.s[ca]ss
        # /js/app.js -> views/js/app.coffee
        case ext
        when 'css'
          if found = Dir.glob(template_path("#{path}.s[ca]ss")).first
            template = Tilt.new(found, nil, settings.sass)
            return response(env, template.class.default_mime_type, ->{template.render},
              get_mtime(template.file, *sass_dependencies(template)))
          end
        when 'js'
          body = if '/all' == path
            source = javascript_files
            ->{merge_javascripts(source)}
          elsif source = template_path("#{path}.coffee") and File.exist? source
            ->{Tilt.new(source).render}
          end

          return response(env, JS_MIME, body, get_mtime(*source)) if body
        end
      end
      app.call(env)
    end

    def sass_dependencies(template)
      template.instance_variable_get('@engine')
        .dependencies.map { |s| s.options[:filename] }
        .select { |f| f.index(settings.root) == 0 }
    end

    def javascript_files
      settings.js_assets.map do |name|
        name.end_with?('.coffee') ? template_path(name) : File.join(settings.public_folder, name)
      end
    end

    def merge_javascripts(files)
      require 'uglifier' unless defined? Uglifier
      Uglifier.new.compile files.map { |name|
        name.end_with?('.js') ? File.read(name) : Tilt.new(name).render
      }.join(";")
    end

    def get_mtime(*files)
      files.map { |f| File.mtime(f) }.max
    end

    def response(env, mime_type, body, mtime = nil)
      status, headers = 200, {}
      if mtime
        expires_at = Time.now + expires_in
        headers['Expires'] = expires_at.httpdate
        headers['Cache-control'] = "public, must-revalidate, max-age=#{expires_in}"
        headers['Last-modified'] = mtime.httpdate
        if client_time = env['HTTP_IF_MODIFIED_SINCE'] and Time.httpdate(client_time) >= mtime
          status, body = 304, ""
        else
          headers['Content-type'] = mime_type
        end
      end
      body = body.call if body.respond_to? :call
      [status, headers, Array(body)]
    end
  end

  module Helpers
    def javascript_assets
      settings.js_assets
    end

    def javascript_includes_names
      if settings.production? then %w[/all.js]
      else javascript_assets.map {|f| "/#{File.basename(f, '.*')}.js" }
      end
    end

    def javascript_includes
      javascript_includes_names.map {|a| %(<script src="#{a}"></script>) }.join("\n")
    end
  end

  def self.registered(app)
    app.helpers Helpers

    app.set :haml, format: :html5

    app.set :sass do
      require 'compass'
      Compass.configuration do |config|
        config.project_path = app.settings.root
        config.sass_dir = app.settings.views
      end

      options = {style: app.settings.production? ? :compressed : :nested}
      options[:cache_location] = File.join(ENV['TMPDIR'], 'sass-cache') if ENV['TMPDIR']
      Compass.sass_engine_options.merge options
    end

    app.use Middleware, app.settings
  end

  Sinatra.register self
end

# monkeypatch to Tilt to enable rendering coffeescript with multibyte
# characters in it
Tilt::CoffeeScriptTemplate.class_eval do
  alias original_prepare prepare
  def prepare
    original_prepare
    data.force_encoding 'UTF-8'
  end
end
