require 'nokogiri'

module RFC
  module HTML
    module Common
      def template_name
        self.class.name.demodulize.underscore
      end
      def classnames() nil end
    end

    Section = Struct.new(:doc, :parent) do
      include Common

      attr_accessor :id, :level, :title
      attr_writer :elements

      def elements
        @elements + sections
      end

      def id?
        id.present?
      end

      def sections
        @sections ||= []
      end

      def short_title() nil end
    end

    Xref = Struct.new(:doc) do
      include Common
      attr_accessor :text, :title, :href
    end

    Figure = Struct.new(:artwork) do
      include Common

      def self.detect(artwork) new(artwork) end

      def id?() false end
      def title?() false end

      def text?() true end

      def text
        unindent(normalized_text)
      end

      def normalized_text
        @normalized_text ||= artwork.rstrip.gsub(/\r|\r\n/, "\n")
      end

      def indentation_size
        @indentation_size ||= begin
          lines = normalized_text.split("\n").reject(&:blank?)
          lines.map {|l| l.match(/^[ \t]*/)[0].to_s.size }.min
        end
      end

      def preamble?() false end
      def postamble?() false end

      def valid?
        indentation_size == 5 || ascii_art?
      end

      # A figure will usually have a lower ratio of word characters to total
      # characters at the beginning of line
      def ascii_art?
        chars = text.scan(/^\s*(\S)/).flatten
        return false if chars.size < 3
        word, non_word = chars.partition {|c| c =~ /[a-zA-Z]/ }
        ratio = word.size / chars.size.to_f
        ratio < 0.5
      end

      def unindent(text)
        text = text.gsub(/^[ \t]{#{indentation_size}}/, '')
        text.sub!(/\A\s+\n/, '')
        text
      end
    end

    class List
      include Common

      BULLET_RE = /\A   (o|\([A-Z]\))  /

      def self.detect?(el)
        el.respond_to?(:to_str) && el.to_str =~ BULLET_RE
      end

      def self.create(elements)
        style = elements.first.match(BULLET_RE)[1] == 'o' ? 'symbols' : 'alpha'
        items = []
        elements.each { |els|
          if els.is_a?(String)
            parts = els.split(/^   (?:o|\([A-Z]\))  /)
            if parts.size > 1
              parts.shift # first one is empty
              parts.each do |part|
                items << Text.new([[part]])
              end
            else
              items.last.elements.first << els
            end
          else
            items.last.elements.first << els
          end
        }
        new(items, style)
      end

      attr_reader :elements, :style

      def initialize(elements, style)
        @elements = elements
        @style = style
      end

      def note?() false end
    end

    Text = Struct.new(:elements) do
      def self.create(elements)
        self.new elements.map { |els|
          if els.is_a?(Array) && List.detect?(els.first)
            List.create(els)
          elsif els.is_a?(Array) && els.size == 1 && Figure.detect(els.first).valid?
            Figure.new(els.first)
          else
            els
          end
        }
      end

      include Common
    end

    class Document
      def self.parse(html)
        doc = self.new
        Parser.parse(html, doc)
        doc
      end

      attr_reader :sections
      attr_accessor :title, :short_title, :display_id

      def initialize
        @sections = []
      end

      def abstract?() false end
      def authors?() false end
      def references?() false end
      def back_sections?() false end

      def create_section(level)
        parent = self
        (level - 2).times { parent = parent.sections.last }
        section = Section.new(self, parent)
        section.level = level
        parent.sections << section
        section
      end

      include Common
    end

    class Parser
      def self.parse(*args)
        new(*args).parse
      end

      attr_reader :doc, :section

      def initialize(html, doc)
        @html = Nokogiri::HTML(html)
        @doc = doc
        @section = nil
      end

      def create_section(level)
        finalize_last_section if section
        @section = doc.create_section(level)
        @raw_elements = []
        block_given? ? yield(@section) : @section
      end

      def ignore_element?(el)
        el.element? && %w[grey invisible].include?(el['class'])
      end

      def in_appendix?
        section && section.id.to_s.start_with?('appendix')
      end

      def parse
        if title = @html.at_css('title')
          title_text = title.text
          if title_text.sub!(/^(\S+ \S+) - /, '')
            doc.display_id = $1
          end
          doc.title = title_text
        end

        each_element do |el|
          if el.element?
            if el['class'] =~ /^h(\d+)$/
              level = $1.to_i
              if section && section.level == level && @raw_elements.none?{|e| e.present? }
                # fix rfc2html bug where long title would get broken into two
                # consecutive SPAN.h3 elements
                section.title << el.text
              else
                if level < 2 && in_appendix?
                  # work around H1 nested in Appendix at level H2 :/
                  # TODO: solve this better
                  level += 2
                end
                selflink = el.at_css('*[name]')
                selflink.remove if selflink
                create_section(level) do |s|
                  s.id = selflink['name'] if selflink
                  s.title = el.text.sub(/\.\s*/, '') unless level == 1
                end
              end
            elsif el['href']
              xref = Xref.new(doc)
              xref.text = el.text
              xref.title = el['title']
              xref.href = el['href']
              add_element(xref)
            else
              add_element "UNRECOGNIZED(#{el.to_s})"
            end
          else
            add_element el.text
          end
        end
        finalize_last_section
      end

      def add_element(el)
        @raw_elements << el if defined? @raw_elements
      end

      def finalize_last_section
        # squash consecutive string elements together to better detect
        # paragraph breaks in the next step
        @raw_elements = @raw_elements.each_with_object([]) do |raw, all|
          if raw.is_a?(String) && all.last.is_a?(String)
            all.last << raw
          else
            all << raw
          end
        end

        elements = [[]]
        @raw_elements.each do |raw|
          if raw.is_a?(String)
            blocks = raw.split(/(\n[ \t]*)+\n/).reject(&:blank?)
            if blocks.any?
              elements.last << blocks.shift
              blocks.each do |block|
                elements << [block]
              end
            end
          else
            elements.last << raw
          end
        end

        text_el = Text.create(elements)
        section.elements = [text_el]
      end

      def each_element
        @html.css('body > pre').each do |pre|
          pre.children.each do |el|
            yield el unless ignore_element?(el)
          end
        end
      end
    end
  end
end
