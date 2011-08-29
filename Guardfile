require 'guard/guard'
require 'fileutils'

class ::Guard::Sass < ::Guard::Guard
  def initialize(watchers = [], options = {})
    super
    require 'sass' unless defined? ::Sass
  end
  
  def run_on_change(paths)
    paths.reject { |p| File.basename(p).index('_') == 0 }.each do |file|
      render_file(file)
    end
  end
  
  def run_all
    all_files = Dir.glob('**/*.*')
    paths = ::Guard::Watcher.match_files(self, all_files)
    run_on_change(paths)
  end
  
  def render_file(file)
    source = File.read(file)
    type = file.match(/\w+$/)[0].to_sym
    outfile = file.sub(/\.\w+$/, '.css')
    content = ::Sass::Engine.new(source, @options.merge(:syntax => type)).render

    File.open(outfile, 'w') { |f| f << content }
    puts "Rendered #{outfile}"
  rescue ::Sass::SyntaxError
    warn "Error processing file: #{$!}"
  end
end

guard 'sass', :style => :compressed do
  watch(/^.+\.s[ca]ss$/)
end

# guard 'livereload', :apply_js_live => false, :grace_period => 0 do
#   ext = %w[js css png gif html md markdown xml]

#   watch(%r{.+\.(#{ext.join('|')})$}) do |match|
#     file = match[0]
#     file unless file =~ /^_(?:site|tmp)\//
#   end
# end
