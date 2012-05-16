Pretty RFC
==========

The goal of this projects is to collect and reformat official RFC documents and
popular drafts.

RFCs, as published officially, are in unsightly and impractical paged format.
What's worse, the official format of most RFCs is plain text, even though they
are authored in richer formats such as XML.

Running the app
---------------

Dependencies:

* git
* Ruby 1.9
* rake
* Bundler
* libxml2
* PostgreSQL

By default, the app will try to connect to the database named "rfc" on localhost
without a username or password. This can be affected with the `DATABASE_URL`
environment variable. If the database doesn't exist, the [boostrap
script][bootstrap] will try to create it.

~~~ sh
# initialize dependencies and database
$ script/bootstrap

# start the server
$ bundle exec rackup

# now visit http://localhost:9292/
~~~

The RFC index
-------------

The [index of all RFCs][index] is pulled from FTP:
ftp://ftp.rfc-editor.org/in-notes/rfc-index.xml

Then the metadata for each RFC entry is imported to the database. This is done
by the ["import_index" rake task][rakefile] as part of the bootstrap process.

The search index
----------------

Searching is done with [PostgreSQL full text searching][textsearch]. The
necessary indexes, stored procedures and triggers for this are in [Searchable][]
module.

The search results ordering is not perfect, but it is improved by bringing in a
[popularity score from faqs.org][pop]. This is done by the ["import_popular" rake
task][rakefile] as part of the bootstrap process.

Fetching and rendering RFCs
---------------------------

When an RFC is first requested and it has never been processed, the app tries to
look up its source XML document and render it to HTML. The XML lookup goes as
follows:

1.  The fetcher tries to find the XML in http://xml.resource.org/public/rfc/xml/
    where some RFCs in the 2000–53xx range can be found.

2.  Failing that, it fetches the metadata for the RFC from
    http://datatracker.ietf.org/doc/

3.  If there is a link to the XML from the datatracker, use that. There probably
    won't be a link, though.

4.  When there is no XML link, the fetcher looks up the draft name for the RFC
    and checks if it can at least find the XML for its draft at
    http://www.ietf.org/id/

**Note:** This process only discovers XML sources for a small subset of RFCs.
This is the biggest problem I have right now. The XML and nroff files in which
RFCs were authored are usually not published, but are archived by rfc-editor.org
and available by request by email.

I'm investigating is there a way for bulk retrieval of these source files.

If unable to obtain them, I will have to reformat RFCs by parsing the current
publications instead of the source XML. This might be a lot of work.

When obtained, the XML is parsed and rendered to HTML by the [RFC][] module.
The templates used for generating HTML are in [templates/][templates].


  [index]:      http://www.rfc-editor.org/getbulk.html
  [rakefile]:   https://github.com/mislav/rfc/blob/master/Rakefile
  [searchable]: https://github.com/mislav/rfc/blob/master/searchable.rb
  [rfc]:        https://github.com/mislav/rfc/blob/master/rfc.rb
  [bootstrap]:  https://github.com/mislav/rfc/blob/master/script/bootstrap
  [templates]:  https://github.com/mislav/rfc/tree/master/templates
  [textsearch]: http://www.postgresql.org/docs/9.1/static/textsearch-intro.html
  [pop]:        http://www.faqs.org/rfc-pop1.html
