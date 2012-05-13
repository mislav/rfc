require 'dm-migrations'
require_relative 'searchable'

class RfcEntry
  include DataMapper::Resource
  extend Searchable

  property :document_id,  String,  length: 10,     key: true
  property :title,        String,  length: 255
  property :abstract,     Text,    length: 2200
  property :keywords,     Text,    length: 500
  property :body,         Text
  property :obsoleted,    Boolean, default: false
  property :publish_date, Date
  property :popularity,   Integer

  def keywords=(value)
    if Array === value
      super(value.empty?? nil : value.join(', '))
    else
      super
    end
  end

  searchable title: 'A', keywords: 'B',
             abstract: 'C', body: 'D'

  def self.get_rfc num
    num.to_s.gsub(/[^a-z0-9]+/i, '') =~ /^([a-z]*)(\d+)$/i
    type, num = $1.to_s.upcase, Integer($2)
    type = 'RFC' if type.empty?
    get "#{type}%04d" % num
  end
end

