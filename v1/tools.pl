#!/usr/bin/perl -w

# ==========================================================================
# tools.pl
#
# A bunch of tools to validate some basic stuff.  Like, how many posts do
# we see from each mailing list?
#
# ==========================================================================
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
use Data::Dumper;
use DBI;

my $dbh;

# ==========================================================================
# FUNCTIONS/SUBROUTINES
# ==========================================================================

sub count_distinct_lists {
  my $i;
  my %distinct_lists;
  my $query = 
    'SELECT msgid FROM ml';
  my $res = $dbh->selectall_arrayref($query);

  foreach (@$res) {
    foreach $i (0..$#$_) {
      $_->[$i] =~ m|archives/([^/]*)/|;
      $distinct_lists{"$1"} += 1;
    }
  }

  foreach my $listname (keys %distinct_lists) {
    print "$listname: $distinct_lists{$listname}\n";
  }
}

# ==========================================================================
# MAIN BLOCK
# ==========================================================================

$dbh = DBI->connect( "dbi:SQLite:ml.db" ) || 
  die "Cannot connect: $DBI::errstr";

count_distinct_lists;

# ==========================================================================
# SAMPLE CODE SNIPPETS.
# ==========================================================================
#my $dbh = DBI->connect( "dbi:SQLite:ml.db" ) || die "Cannot connect: $DBI::errstr";
#my $res = $dbh->selectall_arrayref ( q(
#  SELECT *
#  FROM ml
#  WHERE msgid like '%func-list%'
#));

#foreach (@$res) {
#  foreach $i (0..$#$_) {
#    print "$_->[$i] "
#  }
#  print "\n";
#}

#$dbh->disconnect;


#============================
# Partial queries

#%pq = (
#  'func' => 'msgid like "%func-list%"',
#  'freeipa-devel' => 'msgid like "%freeipa-devel%"',
#  'et-mgmt-list' => 'msgid like "%et-mgmt-list"',
#  'redhat' => 'author_email like "%redhat%"',
#  'not-redhat' => 'author_email not like "%redhat%"',
#  'patch' => 'subject like "%PATCH%"'
#);

# $testquery = "select timedate from ml where $pq{'func'}";
# $testcmd = "sqlite3 ml.db '$testquery'";
# print "cmd is $testcmd\n";
# $result = `$testcmd`;
# @timedates = split("/n", $result);
# @sorteddates = sort(@timedates);
# foreach $timedate (@timedates) {
#  print "Got a date: $timedate\n";
# }
# print "first date is $sorteddates[0], last date is $sorteddates[-1]\n";a
#
# ------------------------


