task :environment do
  require 'bundler'
  Bundler.setup
  require_relative 'app'
end

namespace :db do
  task :rebuild => :environment do
    DataMapper.auto_migrate!
  end

  task :migrate => :environment do
    DataMapper.auto_upgrade!
  end
end

task :import_index => ['tmp/rfc-index.xml', :environment] do |task|
  require 'nokogiri'
  require 'active_support/core_ext/object/try'

  DataMapper.logger.set_log($stderr, :warn)

  index = Nokogiri File.open(task.prerequisites.first)

  index.search('rfc-entry').each do |xml_entry|
    entry = RfcEntry.new
    entry.document_id = xml_entry.at('./doc-id').text
    entry.title       = xml_entry.at('./title').text
    entry.abstract    = xml_entry.at('./abstract').try(:inner_html)
    entry.keywords    = xml_entry.search('./keywords/*').map(&:text)
    entry.save!
  end
end

file 'tmp/rfc-index.xml' do |task|
  mkdir_p 'tmp'
  index_url = 'ftp://ftp.rfc-editor.org/in-notes/rfc-index.xml'
  sh 'curl', '-#', index_url, '-o', task.name
end
