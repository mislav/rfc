require_relative 'rfc'

class RfcDocument
  extend Forwardable

  attr_reader :entry
  def_delegators :entry, :title, :abstract, :body, :publish_date

  def_delegator :entry, :document_id, :id
  def_delegator :entry, :obsoleted,   :obsoleted?
  def_delegator :entry, :updated_at,  :last_modified

  class << self
    alias_method :wrap, :new

    def search query, options = {}
      RfcEntry.search_raw(query, options).map {|e| wrap e }
    end

    def fetch doc_id
      entry = RfcEntry.get doc_id
      entry ? wrap(entry) : yield
    end
  end

  def initialize entry
    @entry = entry
  end

  def external_url
    "http://datatracker.ietf.org/doc/#{id.downcase}/"
  end

  def pretty?
    !entry.body.nil?
  end

  def make_pretty href_resolver
    if entry.fetcher_version.nil?
      fetcher = RfcFetcher.new self.id
      entry.xml_source = fetcher.xml_url
      entry.fetcher_version = fetcher.version

      if fetcher.fetchable?
        fetcher.fetch
        doc = File.open(fetcher.path) {|file| RFC::Document.new file }
        doc.href_resolver = href_resolver
        entry.body = RFC::TemplateHelpers.render doc
      end
      entry.save
    end
  end
end

require 'dm-migrations'
require 'dm-timestamps'
require_relative 'searchable'

class RfcEntry
  include DataMapper::Resource
  extend Searchable

  property :document_id,     String,  length: 10,     key: true
  property :title,           String,  length: 255
  property :abstract,        Text,    length: 2200
  property :keywords,        Text,    length: 500
  property :body,            Text
  property :obsoleted,       Boolean, default: false
  property :publish_date,    Date
  property :popularity,      Integer
  property :xml_source,      String,  length: 100
  property :fetcher_version, Integer

  timestamps :updated_at

  class << self
    def get doc_id
      super normalize_document_id(doc_id)
    end

    private

    def normalize_document_id doc_id
      doc_id.to_s.gsub(/[^a-z0-9]+/i, '') =~ /^([a-z]*)(\d+)$/i
      type, num = $1.to_s.upcase, $2.to_i
      type = 'RFC' if type.empty?
      "#{type}%04d" % num
    end
  end

  def keywords=(value)
    if Array === value
      super(value.empty?? nil : value.join(', '))
    else
      super
    end
  end

  searchable title: 'A', keywords: 'B',
             abstract: 'C', body: 'D'
end

require 'fileutils'
require 'net/http'
require 'nokogiri'

class RfcFetcher
  XML_URL     = 'http://xml.resource.org/public/rfc/xml/%s.xml'
  DRAFTS_URL  = 'http://www.ietf.org/id/'
  TRACKER_URL = 'http://datatracker.ietf.org/doc/%s/'

  class << self
    attr_accessor :download_dir

    def version() 1 end
  end
  self.download_dir = File.join(ENV['TMPDIR'] || '/tmp', 'rfc-xml')

  attr_reader :path

  def initialize doc_id
    @doc_id = doc_id.to_s.downcase
  end

  def version() self.class.version end

  def xml_url
    return @xml_url if defined? @xml_url
    @xml_url = find_xml
  end

  def fetchable?
    !xml_url.nil?
  end

  def fetch
    @path = File.join self.class.download_dir, @doc_id + '.xml'
    unless File.exist? @path
      FileUtils.mkdir_p File.dirname(@path)
      system 'curl', '--silent', xml_url.to_s, '-o', @path
    end
  end

  def request url
    url = URI(url) unless url.respond_to? :host
    res = Net::HTTP.start(url.host, url.port) {|http| yield http, url.request_uri }
    res.error! if Net::HTTPServerError === res
    res
  end

  def http_exist? url
    Net::HTTPOK === request(url) {|http, path| http.head path }
  end

  def find_xml
    xml_url = XML_URL % @doc_id
    if @doc_id.start_with? 'rfc' and http_exist? xml_url
      xml_url
    else
      find_tracker_xml
    end
  end

  def get_html url
    res = request(url) {|http, path| http.get path }
    yield Nokogiri(res.body) if Net::HTTPOK === res
  end

  def find_tracker_xml
    get_html TRACKER_URL % @doc_id do |html|
      if href = html.at('//table[@id="metatable"]//a[text()="xml"]/@href')
        href.text
      elsif html.search('#metatable td:nth-child(2)').text =~ /^Was (draft-[\w-]+)/
        find_draft_xml $1
      end
    end
  end

  def find_draft_xml draft_name
    drafts_url = URI(DRAFTS_URL)
    get_html drafts_url do |html|
      html.search("a[href*=#{draft_name}]").
        map {|link| (drafts_url + link['href']).to_s }.
        select {|href| File.basename(href, '.xml') =~ /^#{draft_name}(-\d+)?$/ }.
        sort.last
    end
  end
end
