require 'sinatra/base'

# Adds functionality to template rendering methods to call last_modified with
# the template's timestamp before actually rendering it.
#
# Examples
#
#   erb :index, auto_last_modified: true
#
#   # with extra timestamp:
#   erb :show, auto_last_modified: @item.updated_at
module AutoLastModified
  module TiltExt
    def mtime
      @mtime ||= File.mtime file
    end
  end

  module SinatraExt
    private
    def compile_template(engine, data, options, views)
      set_mtime = options.delete :auto_last_modified
      template = super
      if set_mtime
        mtime = template.mtime
        mtime = set_mtime if set_mtime.respond_to? :hour and set_mtime > mtime
        last_modified mtime
      end
      template
    end
  end

  Tilt::Template.send :include, TiltExt
  Sinatra::Base.send  :include, SinatraExt
end
