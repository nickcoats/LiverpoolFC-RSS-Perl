#!/usr/bin/perl

#################################################################
#
# Name: liverpoolFC_RSS_Imports.pl
#
# Author: Nick Coats
#
# Desc: This script is used to fetch RSS media from a variety of
#		online sources and store the data in a database. To use, 
#		you must first pull a list of RSS link sources. As you loop
#		through them, run the general_rss_parse sub with the source
#		link and id passed as the parameters. The scripts ends by uploading
#		all of the rss media results into a table and triming the entire
#		media set in that table to 50. This script was meant to be ran
#		as a cron job.
#
#################################################################

use cPanelUserConfig;
use FindBin;
use lib "$FindBin::Bin/";

use strict;
use warnings;
use Data::Dumper;
use XML::RSS::Parser::Lite;
use LWP::Simple;
use Database;

# database connection
my $dbh = &Database::fetch_dbh();


#! Run Import Subs Here
# -------------------------------------------------------------

&fetch_rss_sources();








#################################################################
#
# Name: fetch_rss_sources
#
# Params: none
#
# Desc: Fetch list of rss sources to parse and import media.
#
#################################################################

sub fetch_rss_sources
{
	my $query = "SELECT id, source_link FROM rss_news_sources";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	 
	# loop through tickers and get historical data and std dev's 
	while(my $row = $sth->fetchrow_hashref){
		&general_rss_parse($row->{source_link}, $row->{id});
	}	
	
	# keep fresh data, only the last 50 articles
	my $latest_id_list = &get_trim_ids();
	&trim_dated_media($latest_id_list);
	
	print "\nNew RSS Media Upload Complete.\n\n";
	
	return;
}



#################################################################
#
# Name: General RSS Parse
#
# Param: rss source link, source id
#
# Desc: This sub routine works with all sources that do not need
#       special parsing. 
#
#################################################################

sub general_rss_parse
{
	my $source = $_[0];
	my $xml = get("$source");
	my $rp = new XML::RSS::Parser::Lite;
	$rp->parse($xml);
	
	for (my $i = 0; $i < $rp->count(); $i++) {
	    my $it = $rp->get($i);
		#print "Title:" . $it->get('title') . "\nURL: " . $it->get('url') . "\nPublished: " . $it->get('pubDate') . "\n\n";
		
		if($_[1] == 3 || $_[1] == 6 || $_[1] == 7 || $_[1] == 8){ 
			# parse the titles on news sources 1 and 3 to make sure they're about LFC
			if($it->get('title') =~ m/Liverpool/i){
				#print "Title:" . $it->get('title') . "\nURL: " . $it->get('url') . "\nPublished: " . $it->get('pubDate') . "\n\n";
				
				if($_[1] == 6){
					if($it->get('category') eq 'Echo' || $it->get('category') eq 'Daily Mail' || $it->get('category') eq 'Tribal Football'){
						next; # don't capture data from LFCLive that comes from the echo
					}
				}
				
				my $media_check = &check_existing_media($_[1], $it->get('url'));
				if($media_check == 0){
					
					my $title = $it->get('title');
					$title =~ s/^\s+|\s+$//g;
					
					my $url = $it->get('url');
					$url =~ s/^\s+|\s+$//g;
					
					my $pubDate = substr($it->get('pubDate'), 5);
					# clean the published times
					if(substr($pubDate, -5) eq '+0000'){ 
						$pubDate = substr($pubDate, 0, -5);
					} elsif(substr($pubDate, -4) eq ' GMT'){
						$pubDate = substr($pubDate, 0, -4);
					}
					
					my $media_img = &generate_player_images($it->get('title'));
					
					&input_new_media($_[1], $title, $url, $pubDate, $media_img);
				}
			}	
		} else {
			my $media_check = &check_existing_media($_[1], $it->get('url'));
			if($media_check == 0){
				
				my $title = $it->get('title');
				$title =~ s/^\s+|\s+$//g;
				
				my $url = $it->get('url');
				$url =~ s/^\s+|\s+$//g;
				
				my $pubDate = substr($it->get('pubDate'), 5);
				# clean the published times
				if(substr($pubDate, -5) eq '+0000'){
					$pubDate = substr($pubDate, 0, -5);
				} elsif(substr($pubDate, -4) eq ' GMT'){
					$pubDate = substr($pubDate, 0, -4);
				}
				
				my $media_img = &generate_player_images($it->get('title'));
				
				&input_new_media($_[1], $title, $url, $pubDate, $media_img);
			}		        
		}	
	}
}



#################################################################
#
# Name: input_new_media
#
# Params: source_id, title, url, date published
#
# Desc: input new media into rss_media table.
#
#################################################################

sub input_new_media
{
	my $query = "INSERT INTO rss_media (source_id, title, url, date_published, media_image) VALUES (?,?,?,?,?)";
	my $sth = $dbh->prepare($query);
	$sth->execute(($_[0],  $_[1], $_[2], $_[3], $_[4]));
	
	return;
}



#################################################################
#
# Name: check_existing_media
#
# Params: source id, url
#
# Desc: check to see if we already have that link from that source
#
#################################################################

sub check_existing_media
{
	my $query = "SELECT id FROM rss_media WHERE source_id = ? AND url = ?";
	my $sth = $dbh->prepare($query);
	$sth->execute(($_[0], $_[1]));
	 
	my $result = $sth->rows; 
	
	return $result;
}


#################################################################
#
# Name: trim_dated_media
#
# Params: deleted id list
#
# Desc: deleted old articles, only keep the most recent 50
#
#################################################################

sub trim_dated_media
{
	my $id_list = $_[0];
	my $query = "DELETE FROM rss_media WHERE id NOT IN ($id_list)";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	
	return;
}


#################################################################
#
# Name: get_trim_ids
#
# Params: none
#
# Desc: get the most recent 50 ids to keep
#
#################################################################

sub get_trim_ids
{
	my $query = "SELECT id FROM rss_media ORDER BY id DESC LIMIT 50";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	
	my @ids; 
	while( my $row = $sth->fetchrow_hashref){
		push(@ids, "'".$row->{id}."'");
	}
	
	my $id_list = join(',',@ids);
	
	return $id_list;
}


#################################################################
#
# Name: generate_player_images
#
# Params: title
#
# Desc: regex check media title for specific names and assign img
#
#################################################################

sub generate_player_images
{
	my $media_title = $_[0];
	my $player_image;
	my $range = 3;
	
	if($media_title =~ m/gerrard/i){
		my $random_number = int(rand($range));
		if($random_number > 0){
			$random_number = $random_number + 1;
			$player_image = "gerrard$random_number";
		} else {
			$player_image = "gerrard";
		}	
	} elsif($media_title =~ m/sturridge/i){
		my $random_number = int(rand($range));
		if($random_number > 0){
			$random_number = $random_number + 1;
			$player_image = "sturridge$random_number";
		} else {
			$player_image = "sturridge";
		}
	} elsif($media_title =~ m/sterling/i){
		my $random_number = int(rand($range));
		if($random_number > 0){
			$random_number = $random_number + 1;
			$player_image = "sterling$random_number";
		} else {
			$player_image = "sterling";
		}
	} elsif($media_title =~ m/coutinho/i){
		$player_image = "coutinho";
	} elsif($media_title =~ m/balotelli/i){
		$player_image = "balotelli";
	} elsif($media_title =~ m/henderson/i){
		$player_image = "henderson";
	} elsif($media_title =~ m/skrtel/i){
		$player_image = "skrtel";
	} elsif($media_title =~ m/johnson/i){
		$player_image = "johnson";
	} elsif($media_title =~ m/toure/i){
		$player_image = "toure";
	} elsif($media_title =~ m/mignolet/i){
		$player_image = "mignolet";
	} elsif($media_title =~ m/lucas/i){
		$player_image = "lucas";
	} elsif($media_title =~ m/lovren/i){
		$player_image = "lovren";
	} elsif($media_title =~ m/sahko/i){
		$player_image = "sahko";
	} else {
		my $random_number = int(rand($range));
		if($random_number == 0){
			$player_image = "team";
		} elsif($random_number == 1){
			$player_image = "kop";
		} elsif($random_number == 2){
			$player_image = "anfield";
		}	
	}
	
	return $player_image;
}







