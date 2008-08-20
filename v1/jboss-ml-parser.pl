#!/usr/bin/perl

# Mailing list measurement script.
# For use with JBoss Pipermail 0.09 (Mailman).
#
# usage: mlparser 
#    --url=[archive url]
#
# What it does:
#  -1. Create a sqlite db if it doesn't already exist.
#   0. wget the archive page into temp space;
#   1. Pull all "author sort" pages from archive page and put them in an array;
#   2. wget the author summary pages and analyze them;
#   3. create a report.

$tmpdir = "/tmp";
%month = (
  'jan' => '01', 
  'feb' => '02',
  'mar' => '03',
  'apr' => '04',
  'may' => '05',
  'jun' => '06',
  'jul' => '07',
  'aug' => '08',
  'sep' => '09',
  'oct' => '10',
  'nov' => '11',
  'dec' => '12'
);

use Getopt::Long;
GetOptions( "url=s" => \$index_url );
if ($index_url eq '') {
  print "$0: mailing list measurement tools\n";
  print "Sample usage: $0 --url=\"https://www.redhat.com/archives/fedora-list\"\n";
  exit (0);
}

# Create a sqlite db.  Schema as follows:
#   ml
#     msgid		varchar(255)	The url to the message -- unique id;
#     author_name	varchar(255)	The name of the author;
#     author_email	varchar(255)	The email of the author;
#     subject		varchar(255)	Subject line of the email;
#     timedate		varchar(255)	Time/date stamp (varchar for now)

$sqlite_result = `sqlite3 ml.db 'create table ml(msgid varchar(255),author_name varchar(255),author_email varchar(255), subject varchar(255), timedate varchar(255))'`;

# Get the archive index and pull all the individual month entries from it,
# and then walk through the months one at a time, and then walk thru 
# individual emails, and shove entries into the DB.

$wget_result = `wget -O $tmpdir/archive_index.html $index_url`;
open (ARCHIVE_INDEX, "$tmpdir/archive_index.html") or die;
while (<ARCHIVE_INDEX>)
{
  if (m|href=\"(.*)/date\.html|) {
    $month_url = $1;
    $full_month_url = $index_url . "/" . $month_url;
    $date_url = $full_month_url . "/date.html";
    print "Found $month_url\n";
    $wget_result = `wget -O $tmpdir/$month_url $date_url`;
    print "Parsing $month_url\n";
    open (MONTH_FILE, "$tmpdir/$month_url") or die;
    while (<MONTH_FILE>) {
      # <LI><A HREF="000001.html">[hibernate-dev] hibernate-hsqldb-testsuite...
      if (m|^<LI><A HREF="([^"]*)">|) {
        $msg_url = "$1";
        $full_msg_url = "$full_month_url/$msg_url";
        $wget_cmd = "wget -O $tmpdir/$msg_url $full_msg_url";
        # print "$wget_cmd\n";
        $wget_result = `$wget_cmd`;
        open (MSG_FILE, "$tmpdir/$msg_url") or die;
        $author_name = '';
        $author_email = '';
        $subject = '';
        $timedate = '';
	undef $/;  # SLURP!
        while (<MSG_FILE>) {
	    # if (m|<H1>(.*)</H1>/s+<B>(.*)</B>/s+<A[^>]*>(.*)</A><BR>/s+<I>(.*)</I>|s) {
	    if (m|<H1>([^<]*)</H1>\s*<B>([^<]*)</B>\s+<A[^>]*>([^<]*)</A><BR>\s+<I>([^<]*)</I>|sm) {
	    $subject = $1;
	    $author_name = $2;
	    $author_email = $3;
	    $timedate = $4; 
	    $subject =~ s/\s{2,}/ /g;
	    $subject =~ s/\s*$//g;
	    $author_name =~ s/\s{2,}/ /g;
	    $author_name =~ s/\s*$//g;
	    $author_email =~ s/\./ /g;
	    $author_email =~ s/ at / /g;
	    $author_email =~ s/\s{2,}/ /g;
	    $author_email =~ s/\s*$//g;
	    $timedate =~ s/\s{2,}/ /g;
            # A bunch of datestamp manipulation jackassery
	    ($dx, $dmon, $dday, $dx, $dx, $dyear) = 
	      ($timedate =~ m|(\w+)\s+(\w+)\s+(\d+)\s+([\d:]+)\s+(\w+)\s+(\d+)|);
            if (length($dday) == 1) { $dday = '0' . $dday; }
            $dbdate = "$dyear-" . $month{lc($dmon)} . "-$dday";
	    # print "---\n  * $full_msg_url\n  * $subject\n  * $author_name\n  * $author_email\n  * $dbdate\n";
          }
        }
        close MSG_FILE;
	$/ = "\n";  # UNSLURP!
        # strip $subject of scary characters that screw up the DB
        $subject =~ s/'/!/g;
        $subject =~ s/;/!/g;
        # DIRTY LIKE ZEBRA.  Do not EVER write code like this, it's AWFUL.
        $sqlite_query = "sqlite3 ml.db \"insert into \'ml\' values (\'$full_msg_url\',\'$author_name\',\'$author_email\',\'$subject\',\'$dbdate\')\"";
        # print "$sqlite_query\n";
        $sqlite_result = `$sqlite_query`;
        exit(0) if ($sqlite_result ne '');
      }
    }
    close MONTH_FILE;
  }
}
close ARCHIVE_INDEX;

