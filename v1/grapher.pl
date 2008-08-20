#!/usr/bin/perl

# ==========================================================================
# grapher.pl
#
# usage: grapher.pl [report1 ... reportn]
#   ...where report can be any of a set of predefined reports.
#   ...once that's implemented, of course.
#
# Grapher reads the ml.db file created by the mailing list parser and
# generates lots of human-readable graphs.  Want to know how many of
# the posts to func-list were patches, and how many of those patches came
# from Redhatters versus non-Redhatters?  Grapher is the tool for you!
#
# It's a bunch of terrible hacks, of course, but since I'm not an engineer
# anymore, that's all I'm capable of.  Shoot me.
#
# ==========================================================================
#
# For notes on how to use GD::Graph:
# http://linuxgazette.net/issue83/padala.html
#
# ml.db schema:
# CREATE TABLE ml(msgid varchar(255),author_name varchar(255),author_email 
# varchar(255), subject varchar(255), timedate varchar(255));
#
# Quick DBI Tutorial: http://freshmeat.net/articles/view/1428/
# Some DBI commands:
# $dbh->do( "CREATE TABLE authors ( lastname, firstname )" );
# $dbh->do( "INSERT INTO authors VALUES ( 'Conway', 'Damian' ) " );
# $res = $dbh->selectall_arrayref( q( SELECT a.lastname, a.firstname, b.title
#                                     FROM books b, authors a
#                                     WHERE b.title like '%Orient%'
#                                     AND a.lastname = b.author ) );
# foreach( @$res ) {
#     foreach $i (0..$#$_) {
#         print "$_->[$i] "
#     }
#     print "\n";
# }
# ==========================================================================

use strict;
use lib qw(/home/gregdek/lib/perl5/);
use GD::Graph::pie;
use GD::Graph::lines;
use GD::Graph::colour qw(:colours :lists :files :convert);
use Data::Dumper;
use DBI;

my $dbh;

# ==========================================================================
# FUNCTIONS/SUBROUTINES
# ==========================================================================

sub linechart_participants_over_time_by_domain {

  my $list_title = shift;
  my $graph_title = "$list_title participants by domain";
  my $file_name = "EKG-GRAPHS/$list_title-linechart-participants-over-time-by-domain.png";
  my $sth;
  my @data;
  my @graph_data;
  my @graph_legend;
  my %months_seen;
  my %domains_seen;
  my %months_by_domain;
  my %domains_by_month;
  my $month_iterator;
  my $domain_iterator;

  my $query = 
    'SELECT author_email, timedate FROM ml WHERE msgid like ?';

  $sth = $dbh->prepare($query)
    or die "Couldn't prepare statement: " . $dbh->errstr;

  $sth->execute("%$list_title%") 
    or die "Couldn't execute statement: " . $sth->errstr;
 
  my $totalseen;
  while (@data = $sth->fetchrow_array()) {
    $totalseen++;
    my $email = $data[0];
    my $month = $data[1]; 
    my $domain;
    $month =~ s/-\d\d$//;
    $email =~ /([\w-]+) ([\w-]+) ([\w-]+)$/;
    my $last = $3;
    my $secondlast = $2;
    my $thirdlast = $1;
    if (($last eq '') || ($secondlast eq '')) {
      # $contrib_domains{"undefined"} += 1;
      $domain = 'undefined';
    }
    elsif (($secondlast eq 'com') || ($secondlast eq 'co')) {
      # $contrib_domains{"$thirdlast.$secondlast.$last"} += 1;
      $domain = "$thirdlast.$secondlast.$last";
    }
    else {
      # $contrib_domains{"$secondlast.$last"} += 1;
      $domain = "$secondlast.$last";
    }
    $domains_seen{$domain} += 1;
    $months_seen{$month} = 1;
    $months_by_domain{$month}{$domain} += 1;
    $domains_by_month{$domain}{$month} += 1;
  }

  # Squash domains that are less than 1% into "various" by month
  my $domain_hits;
  foreach $domain_iterator (keys %domains_seen) {
    # print "Domain seen: $domain_iterator\n";
    # print "Domain count: $domains_seen{$domain_iterator}\n";
    # print "Total seen: $totalseen\n";
    # print "Percentage: " . $domains_seen{$domain_iterator}/$totalseen . "\n";
    if ($domains_seen{$domain_iterator}/$totalseen < 0.05) {
      # print "  Too small!\n";
      for $month_iterator (sort keys %months_seen) {
        $domains_seen{'various'} += ($domains_by_month{$domain_iterator}{$month_iterator});
        $domains_by_month{'various'}{$month_iterator} += $domains_by_month{$domain_iterator}{$month_iterator};
	# print "Adding $domains_by_month{$domain_iterator}{$month_iterator} to various for $month_iterator (now $domains_by_month{'various'}{$month_iterator})\n";
	# undef (% {$domains_by_month{$domain_iterator}{$month_iterator}});
	delete($domains_seen{$domain_iterator});
      }
    }
  }
  # print "New domains seen:\n";
  # print Dumper(%domains_seen);

  # A reminder from the Perl data structures bible about how this stuff
  # is actually accessed from a multidimensional hash:

  #foreach $family ( keys %HoH ) {
  #  print "$family: { ";
  #  for $role ( keys %{ $HoH{$family} } ) {
  #    print "$role=$HoH{$family}{$role} ";
  #  }
  #  print "}\n";
  #}

  # shove months_seen into graph_data[0]
  my @months_seen_array;
  foreach $month_iterator (sort keys %months_seen) {
    push @{$graph_data[0]}, $month_iterator;
  }
  
  my $month_counter;
  my $domain_counter = 0;
  foreach $domain_iterator (sort keys %domains_seen) {
    $graph_legend[$domain_counter] = $domain_iterator;
    $domain_counter++;
    for $month_iterator (sort keys %months_seen) {
      # why the hell I need to cast this as int, I don't know, 
      # but since some of these values are coming thru us strings,
      # better safe than sorry
      push @{$graph_data[$domain_counter]}, int($domains_by_month{$domain_iterator}{$month_iterator});
    }
  }
  my @colours = [colour_list(scalar @graph_legend)];
  # print Dumper (@colours);
  # print Dumper (@graph_data);
  # print Dumper (@graph_legend);

  my $mygraph = GD::Graph::lines->new(scalar(keys %months_seen)*40, 600);
  $mygraph->set(
    x_label     => 'Month',
    y_label     => 'Posts',
    title       => $graph_title,
    line_width  => 2,
    dclrs       => @colours
  ) or warn $mygraph->error;

  $mygraph->set_legend_font(GD::gdMediumBoldFont);
  $mygraph->set_legend(@graph_legend);
  my $myimage = $mygraph->plot(\@graph_data) or die $mygraph->error;

  open (GRAPHFILE, ">$file_name");
  print GRAPHFILE $myimage->png;
  close GRAPHFILE;
}

# ==========================================================================

sub piechart_participants_by_domain {
  my $list_title = shift;
  my $graph_title = "$list_title participants by domain";
  my $file_name = "EKG-GRAPHS/$list_title-piechart-participants-by-domain.png";
  my $j = '';
  my $domain;
  my %contrib_domains;
  my %output_domains;
  my @graph_data;
  my $query = 
    "SELECT author_email FROM ml WHERE msgid like '%$list_title%'";
  my $res = $dbh->selectall_arrayref($query);

  my $totalseen = scalar(@$res);  # length of returned array
  # print "Total seen: $totalseen\n";
  foreach (@$res) {
    foreach $j (0..$#$_) {
      $_->[$j] =~ /([\w-]+) ([\w-]+) ([\w-]+)$/;
      my $last = $3;
      my $secondlast = $2;
      my $thirdlast = $1;
      if (($last eq '') || ($secondlast eq '')) {
        $contrib_domains{"undefined"} += 1;
	#print "...UNDEFINED!\n";
      }
      elsif (($secondlast eq 'com') || ($secondlast eq 'co')) {
        $contrib_domains{"$thirdlast.$secondlast.$last"} += 1;
      }
      else {
        $contrib_domains{"$secondlast.$last"} += 1;
      }
    }
  }

  # HACK ALERT: we need to work around an ugly bug in GD::graph here,
  # which is almost certainly related to having too many parameters
  # (since it manifests itself in the huge kickstart-devel-list.)
  # If a domain represents less than 1% of all emails, we will roll
  # it into a "various (COUNT)" chunk, and remap results into the
  # %output_domains hash.  I'm sure there's some schwarzian transform
  # that does this more elegantly.
  
  foreach $domain (keys %contrib_domains) {
    if ($contrib_domains{$domain}/$totalseen < 0.01) {
      $output_domains{'various'} += $contrib_domains{$domain};
    }
    else {
      $output_domains{$domain} = $contrib_domains{$domain};
    }
  }

  foreach $domain (keys %output_domains) {
    # print "$domain $output_domains{$domain}\n";
    push @{$graph_data[0]}, "$domain ($output_domains{$domain})";
    push @{$graph_data[1]}, $output_domains{$domain};
  }

  # print Dumper(@graph_data);

  my $mygraph = GD::Graph::pie->new(1000, 600);
  $mygraph->set(
    title       	=> $graph_title,
    suppress_angle 	=> 10
  ) or warn $mygraph->error;
  
  $mygraph->set_value_font(GD::gdMediumBoldFont);
  my $myimage = $mygraph->plot(\@graph_data) or die $mygraph->error;

  open (GRAPHFILE, ">$file_name");
  print GRAPHFILE $myimage->png;
  close GRAPHFILE;
  return 0;
}

# ==========================================================================
# MAIN BLOCK
# ==========================================================================

$dbh = DBI->connect( "dbi:SQLite:ml.db" ) || 
  die "Cannot connect: $DBI::errstr";

#piechart_participants_by_domain('func-list');
#piechart_participants_by_domain('et-mgmt-tools');
#piechart_participants_by_domain('freeipa-devel');
#piechart_participants_by_domain('anaconda-devel-list');
#piechart_participants_by_domain('hibernate-dev');
linechart_participants_over_time_by_domain('func-list');
linechart_participants_over_time_by_domain('freeipa-devel');
linechart_participants_over_time_by_domain('et-mgmt-tools');
linechart_participants_over_time_by_domain('anaconda-devel-list');
# linechart_participants_over_time_by_domain('hibernate-dev');
