require 'active_support/core_ext/hash/except'

## Author: Xavier Shay
#
# Mix this module into a DataMapper::Resource to get fast, indexed full
# text searching.
#
#   class Post
#     include DataMapper::Resource
#     include Searchable
#
#     property :title, String
#     property :body,  Text
#
#     searchable [:title, :body]
#     searchable [:title], :index => :title_only
#   end
#
#   Post.search("hello")
#   Post.search("hello", :index => :title_only)
module Searchable
  def searchable(columns, opts = {})
    opts[:index] ||= 'search'
    __searches[opts[:index]] = columns
  end

  def search(q, opts = {})
    opts[:index] ||= 'search'
    finder = all(opts.except(:index, :conditions).merge(:conditions => [
      "#{opts[:index]}_vector @@ plainto_tsquery('english', ?)", q]))
    finder &= all(opts[:conditions]) if opts[:conditions]
    finder
  end

  def auto_migrate_up!(repository_name)
    super

    __searches.each do |name, columns|
      [
        create_alter_table_sql(repository_name, name),
        create_index_sql(repository_name, name),
        create_trigger_sql(repository_name, name, columns)
      ].each do |sql|
        repository(repository_name).adapter.execute sql
      end
    end
  end

  private

  def create_alter_table_sql(repository_name, name)
    <<-EOS
      ALTER TABLE #{storage_name(repository_name)}
        ADD COLUMN #{name}_vector tsvector NOT NULL
    EOS
  end

  def create_index_sql(repository_name, name)
    <<-EOS
      CREATE INDEX #{storage_name(repository_name)}_#{name}_vector_idx
        ON #{storage_name(repository_name)} USING gin(#{name}_vector)
    EOS
  end

  def create_trigger_sql(repository_name, name, columns)
    <<-EOS
      CREATE TRIGGER #{storage_name(repository_name)}_#{name}_vector_refresh
        BEFORE INSERT OR UPDATE ON #{storage_name(repository_name)}
      FOR EACH ROW EXECUTE PROCEDURE
        tsvector_update_trigger(#{name}_vector, 'pg_catalog.english',
          #{column_sql(columns)});
    EOS
  end

  def __searches
    @__searches ||= {}
  end

  def column_sql(columns)
    columns.map {|column| send(column).field }.join(", ")
  end
end
