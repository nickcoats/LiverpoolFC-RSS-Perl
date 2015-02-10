# LiverpoolFC-RSS-Perl

This script is used to fetch RSS media from a variety of
online sources and store the data in a database. To use, 
you must first pull a list of RSS link sources. As you loop
through them, run the general_rss_parse sub with the source
link and id passed as the parameters. The scripts ends by uploading
all of the rss media results into a table and triming the entire
media set in that table to 50. This script was meant to be ran
as a cron job.

Basic Usage

# sources 
my @sources = (source_id => 1, link => "www.liverpoolfctestsource.com/news/rss");

# fetch, parse, and import the data
foreach my $source (@sources){
  &general_rss_parse($source['source_id'], $source['link']);
}
