require 'nokogiri'
require 'delegate'
require 'active_support/memoizable'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'
require 'erubis'

module Rfc
  class NodeWrapper < DelegateClass(Nokogiri::XML::Node) 
    extend ActiveSupport::Memoizable

    def template_name
      self.class.name.demodulize.underscore
    end

    def all(path)
      search(path)
    end

    def text_at(path)
      node = at(path) and node.text
    end

    def scope(path)
      old_node = __getobj__
      node = at(path)
      if node then __setobj__(node)
      else raise "no node at #{path.inspect}"
      end

      if block_given?
        begin
          yield self
        ensure
          __setobj__(old_node)
        end
      else
        return self
      end
    end

    def self.define_predicate(name)
      define_method(:"#{name}?") { !self.send(name).blank? }
    end

    def self.method_added(name)
      if public_method_defined?(name) and not method_defined?(:"_unmemoized_#{name}") and
          name !~ /_unmemoized_|_memoizable$|^freeze$|[?!=]$/ and instance_method(name).arity.zero?
        memoize name
        define_predicate name unless method_defined?(:"#{name}?")
      end
    end
  end

  class Author < NodeWrapper
    def name
      self['fullname']
    end

    def role
      self['role']
    end

    def organization
      text_at 'organization'
    end

    def email
      text_at './address/email'
    end

    def url
      text_at './address/uri'
    end
  end

  class Section < NodeWrapper
    attr_reader :level

    def initialize(node, level)
      super node
      @level = level
    end

    def title
      self['title']
    end

    def id
      self['anchor'].presence or title.parameterize
    end

    def elements
      element_children.map do |node|
        case node.name
        when 'section' then Section.new(node, level + 1)
        when 'figure' then Figure.new(node)
        when 't' then Text.new(node)
        else
          raise "unrecognized section-level node: #{node.name}"
        end
      end
    end
  end

  class Xref < NodeWrapper
    def text
      self['target']
    end

    def href
      '#' + self['target'].parameterize
    end
  end

  class Span < NodeWrapper
  end

  class Text < NodeWrapper
    def blocks
      children.each_with_object([[]]) do |node, all|
        if node.element?
          case node.name
          when 'list'
            all << List.new(node) << []
          when 'vspace'
            # presentation element. ignore
          when 'xref'
            all.last << Xref.new(node)
          when 'spanx'
            all.last << Span.new(node)
          else
            $stderr.puts node.inspect if $-d
            raise "unrecognized text-level node: #{node.name}"
          end
        else
          all.last << node
        end
      end
    end

    def list?
      element_children.map(&:node_name) == %w[list]
    end

    def extract_list
      List.new at('./list')
    end
  end

  class List < NodeWrapper
    def elements
      element_children.map do |node|
        case node.name
        when 't' then Text.new(node)
        else
          raise "unrecognized list-level node: #{node.name}"
        end
      end
    end

    def style
      type = self['style']
      type = 'alpha' if type == 'format (%C)'
      type
    end
  end

  class Figure < NodeWrapper
    def id?
      self['anchor'].present?
    end

    def id
      self['anchor'].parameterize
    end

    def title
      self['title']
    end

    def text
      unindent text_at('./artwork')
    end

    def unindent(text)
      text = text.rstrip.gsub(/\r|\r\n/, "\n")
      lines = text.split("\n").reject(&:empty?)
      indentation = lines.map {|l| l.match(/^[ \t]*/)[0].to_s.size }.min
      text.gsub!(/^[ \t]{#{indentation}}/, '').sub!(/\A\s+\n/, '')
    end

    def preamble?
      !!at('./preamble')
    end

    def preamble
      Text.new at('./preamble')
    end
  end

  class Document < NodeWrapper
    def initialize(from)
      super Nokogiri::XML(from)
      scope '/rfc'
    end

    def title
      text_at './front/title'
    end

    def short_title
      text_at './front/title/@abbrev'
    end

    def authors
      all('./front/author').map {|node| Author.new node }
    end

    def sections
      all('./middle/section').map {|node| Section.new(node, 2) }
    end
  end

  module Helpers
    def section_title(section)
      "<h#{section.level}>#{section.title}</h#{section.level}>"
    end
  end

  module TemplateHelpers
    def render(obj, template = obj.template_name)
      file = "templates/#{template}.erb"
      eruby = Erubis::Eruby.new File.read(file), filename: File.basename(file)
      context = SimpleDelegator.new(obj)
      context.extend Helpers
      context.extend TemplateHelpers
      eruby.evaluate(context)
    end
  end
end

rfc = Rfc::Document.new ARGF

if true
  include Rfc::TemplateHelpers
  begin
    puts render(rfc)
  ensure
    $@.delete_if {|l| l.include? '/ruby/gems/' } if $@
  end
end
