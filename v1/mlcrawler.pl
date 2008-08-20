#!/usr/bin/perl

# Mailing list crawler.
#
# usage: mlparser 
#    --url=[top level mailing list manager url]
#
# What it does:
#   1. Walk the list of mailing lists.
#   2. Build a list of all lists with open archives.
#   3. Build a script for mlparser to iterate over.

use Getopt::Long;
GetOptions( "url=s" => \$index_url );
if ($index_url eq '') {
  print "$0: mailing list measurement tools\n";
  print "Sample usage: $0 --url=\"http://www.redhat.com/mailman/listinfo\"\n";
  exit (0);
}

$tmpdir = '/tmp';

$wget_result = `wget -O $tmpdir/all_lists.html $index_url`;
open (ARCHIVE_INDEX, "$tmpdir/all_lists.html") or die;
open (LIST_OF_LISTS, ">lists.txt");
while (<ARCHIVE_INDEX>)
{
  if (m|href=\"(.*listinfo.*)">|) {
    $listurl = $1;
    $listurl =~ s|mailman/listinfo/(.*)|archives/$1|;
    print LIST_OF_LISTS "$listurl\n";
  }
}
close ARCHIVE_INDEX;
