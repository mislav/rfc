require_relative 'rfc'
require 'active_support/core_ext/date_time/conversions'

# The main model which represents an RFC. It delegates persistance to RfcEntry
# and XML fetching to RfcFetcher.
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

    def resolve_url url
      doc_id = File.basename(url).sub(/\.(html|xml|txt)$/, '')
      if doc_id.start_with? 'draft-'
        doc_id.sub!(/-\d+$/, '') # strip draft version
        fetch(doc_id) {
          doc = wrap(RfcEntry.new)
          doc.initialize_draft(doc_id) { yield }
        }
      else
        fetch(doc_id) { yield }
      end
    end
  end

  def initialize entry
    @entry = entry
  end

  def initialize_draft doc_id
    entry.document_id = doc_id
    saved = fetch_and_render do |xml_doc, fetcher|
      entry.title = fetcher.title
      entry.keywords = xml_doc.keywords
      entry.save
    end

    saved ? self : yield
  end

  def external_url
    tracker_id = id =~ /^RFC(\d+)$/ ? ('rfc%d' % $1.to_i) : id.downcase
    "http://datatracker.ietf.org/doc/#{tracker_id}/"
  end

  def pretty?
    !entry.body.nil?
  end

  def make_pretty
    if needs_fetch?
      fetch_and_render
      entry.save
    end
  end

  def needs_fetch?
    entry.fetcher_version.nil? or
      entry.fetcher_version < RfcFetcher.version or
      needs_rerender?
  end

  def needs_rerender?
    entry.body and entry.updated_at.to_time < RFC.last_modified
  end

  def fetch_and_render xml_url = entry.xml_source
    fetcher = RfcFetcher.new self.id, xml_url
    entry.xml_source = fetcher.xml_url
    entry.fetcher_version = fetcher.version

    if fetcher.fetchable?
      fetcher.fetch
      doc = File.open(fetcher.path) {|file| RFC::Document.new file }
      doc.href_resolver = href_resolver
      entry.body = RFC::TemplateHelpers.render doc
      yield doc, fetcher if block_given?
    end
  end

  # Bypass discovery process by explicitly seting a known XML location
  def set_xml_source xml_url
    fetch_and_render xml_url
    entry.save
  end

  # used in the RFC HTML generation phase
  def href_resolver
    ->(xref) { "/#{xref}" if xref =~ /^RFC\d+$/ }
  end
end

require 'dm-migrations'
require 'dm-timestamps'
require_relative 'searchable'

# A lighweight database model that stores metadata and rendered HTML for an RFC.
class RfcEntry
  include DataMapper::Resource
  extend Searchable

  property :document_id,     String,  length: 70,     key: true
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
      if doc_id.to_s =~ /^ rfc -? (\d+) $/ix
        "RFC%04d" % $1.to_i
      else
        doc_id.to_s
      end
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
require 'cgi'
require 'nokogiri'

# Responsible for discovering and fetching of the XML source file for a
# specific publication.
class RfcFetcher
  XML_URL     = 'http://xml.resource.org/public/rfc/xml/%s.xml'
  DRAFTS_URL  = 'http://www.ietf.org/id/'
  TRACKER_URL = 'http://datatracker.ietf.org/doc/%s/'

  class << self
    attr_accessor :download_dir

    def version() 1 end
  end
  self.download_dir = File.join(ENV['TMPDIR'] || '/tmp', 'rfc-xml')

  attr_reader :title, :path

  def initialize doc_id, known_url = nil
    @doc_id = doc_id.to_s.downcase
    @xml_url = known_url unless known_url.nil?
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
      system 'curl', '-L', '--silent', xml_url.to_s, '-o', @path
    end
  end

  def request url
    url = URI(url) unless url.respond_to? :host
    res = Net::HTTP.start(url.host, url.port, *proxy_http_args(url)) { |http|
      yield http, url.request_uri
    }
    res.error! if Net::HTTPServerError === res
    res
  end

  def proxy_http_args(url)
    args = []
    env = "HTTP#{url.scheme == 'https' ? 'S' : ''}_PROXY"
    if proxy_url = (ENV[env] || ENV[env.downcase]) and !proxy_url.empty?
      proxy = URI(proxy_url)
      args << proxy.host << proxy.port
      if proxy.userinfo
        decode = CGI::method(:unescape)
        args.concat proxy.userinfo.split(':', 2).map(&decode)
      end
    end
    args
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
      @title = html.at('//h1/text()').text.strip
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
