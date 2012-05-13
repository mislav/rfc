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
  def searchable(columns, options = {})
    index_name = options.fetch(:index, 'search')
    __searches[index_name] = columns
  end

  def search(query, options = {})
    index_name = options.fetch(:index, 'search')
    finder = all(options.except(:index, :conditions).merge(
      :conditions => ["#{index_name}_vector @@ plainto_tsquery('english', ?)", query]
    ))
    finder &= all(options[:conditions]) if options[:conditions]
    finder
  end

  def search_raw query, options = {}
    limit  = options.fetch(:limit, 50)
    page   = (options[:page] || 1).to_i
    offset = (page - 1)*limit
    repository.adapter.select <<-SQL, query, limit, offset
      SELECT
        document_id, title, abstract, publish_date, obsoleted,
        ts_rank_cd(search_vector, query) AS search_rank
      FROM #{storage_name}, plainto_tsquery('english', ?) query
      WHERE search_vector @@ query
      ORDER BY search_rank DESC
      LIMIT ? OFFSET ?
    SQL
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
    <<-SQL
      ALTER TABLE #{storage_name(repository_name)}
        ADD COLUMN #{name}_vector tsvector NOT NULL
    SQL
  end

  def create_index_sql(repository_name, name)
    <<-SQL
      CREATE INDEX #{storage_name(repository_name)}_#{name}_vector_idx
        ON #{storage_name(repository_name)} USING gin(#{name}_vector)
    SQL
  end

  def create_trigger_sql(repository_name, name, columns)
    table_name = storage_name(repository_name)
    vector_column = "#{name}_vector"

    case columns
    when Array
      column_sql = columns.map {|col| send(col).field }.join(', ')
      trigger = "tsvector_update_trigger(#{vector_column}, 'pg_catalog.english', #{column_sql})"
      create_function = ''
    when Hash
      trigger = "#{table_name}_tsvector_update()"
      create_function = <<-SQL
        CREATE FUNCTION #{trigger} RETURNS trigger AS $$
        begin
          new.#{vector_column} :=
             #{columns.map {|col,w| "setweight(to_tsvector('pg_catalog.english', coalesce(new.#{col},'')), '#{w}')" }.join(" ||\n" + ' '*13)};
          return new;
        end
        $$ LANGUAGE plpgsql;
      SQL
    else
      raise ArgumentError, "unknown type: #{columns.class}"
    end

    <<-SQL
      #{create_function}
      CREATE TRIGGER #{table_name}_#{name}_vector_refresh
        BEFORE INSERT OR UPDATE ON #{table_name}
      FOR EACH ROW EXECUTE PROCEDURE #{trigger};
    SQL
  end

  def __searches
    @__searches ||= {}
  end
end
