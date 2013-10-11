#!/usr/local/groundwork/bin/perl -w
#
#
# check_disk.pl <host> <share> <user> <pass> [warn] [critical] [port]
#
# Nagios host script to get the disk usage from a SMB share
#
# Changes and Modifications
# =========================
# 7-Aug-1999 - Michael Anthon
#  Created from check_disk.pl script provided with netsaint_statd (basically
#  cause I was too lazy (or is that smart?) to write it from scratch)
# 8-Aug-1999 - Michael Anthon
#  Modified [warn] and [critical] parameters to accept format of nnn[M|G] to
#  allow setting of limits in MBytes or GBytes.  Percentage settings for large
#  drives is a pain in the butt
# 2-May-2002 - SGhosh fix for embedded perl
#
# $Id: check_disk_smb.pl,v 1.1.1.1 2005/02/07 19:33:32 hmann Exp $
#
# Added: groundwork specific libs,Tue Jan 17 08:07:39 PST 2006, vnovoselskiy

require 5.004;
use POSIX;
use strict;
use Getopt::Long;
use vars qw($opt_P $opt_V $opt_h $opt_H $opt_s $opt_W $opt_u $opt_p $opt_w $opt_c $verbose);
use vars qw($PROGNAME);
use utils qw(%ERRORS $TIMEOUT &print_revision &support &usage);
use lib qw( /usr/local/groundwork/nagios/libexec );


sub print_help ();
sub print_usage ();

$PROGNAME = "check_disk_smb";

$ENV{'PATH'}='';
$ENV{'BASH_ENV'}=''; 
$ENV{'ENV'}='';

Getopt::Long::Configure('bundling');
GetOptions
	("v"   => \$verbose, "verbose"    => \$verbose,
	 "P=s" => \$opt_P, "port=s"     => \$opt_P,
	 "V"   => \$opt_V, "version"    => \$opt_V,
	 "h"   => \$opt_h, "help"       => \$opt_h,
	 "w=s" => \$opt_w, "warning=s"  => \$opt_w,
	 "c=s" => \$opt_c, "critical=s" => \$opt_c,
	 "p=s" => \$opt_p, "password=s" => \$opt_p,
	 "u=s" => \$opt_u, "username=s" => \$opt_u,
	 "s=s" => \$opt_s, "share=s"    => \$opt_s,
	 "W=s" => \$opt_W, "workgroup=s" => \$opt_W,
	 "H=s" => \$opt_H, "hostname=s" => \$opt_H);

if ($opt_V) {
	print_revision($PROGNAME,'$Revision: 1.1.1.1 $'); #'
	exit $ERRORS{'OK'};
}

if ($opt_h) {print_help(); exit $ERRORS{'OK'};}

my $smbclient= "$utils::PATH_TO_SMBCLIENT " ;
my $smbclientoptions= $opt_P ? "-p $opt_P " : "";


# Options checking

($opt_H) || ($opt_H = shift) || usage("Host name not specified\n");
my $host = $1 if ($opt_H =~ /^([-_.A-Za-z0-9]+\$?)$/);
($host) || usage("Invalid host: $opt_H\n");

($opt_s) || ($opt_s = shift) || usage("Share volume not specified\n");
my $share = $1 if ($opt_s =~ /^([-_.A-Za-z0-9]+\$?)$/);
($share) || usage("Invalid share: $opt_s\n");

($opt_u) || ($opt_u = shift) || ($opt_u = "guest");
my $user = $1 if ($opt_u =~ /^([-_.A-Za-z0-9\\]+)$/);
($user) || usage("Invalid user: $opt_u\n");

($opt_p) || ($opt_p = shift) || ($opt_p = "guest");
my $pass = $1 if ($opt_p =~ /(.*)/);

($opt_w) || ($opt_w = shift) || ($opt_w = 85);
my $warn = $1 if ($opt_w =~ /^([0-9]{1,2}\%?|100\%?|[0-9]+[kMG])$/);
($warn) || usage("Invalid warning threshold: $opt_w\n");

($opt_c) || ($opt_c = shift) || ($opt_c = 95);
my $crit = $1 if ($opt_c =~ /^([0-9]{1,2}\%?|100\%?|[0-9]+[kMG])$/);
($crit) || usage("Invalid critical threshold: $opt_c\n");

# check if both warning and critical are percentage or size
unless( ( ($opt_w =~ /([0-9]){1,2}$/ ) && ($opt_c =~ /([0-9]){1,2}$/ )  )|| (( $opt_w =~ /[kMG]/ ) && ($opt_c =~ /[kMG]/) )  ){
	usage("Both warning and critical should be same type- warning: $opt_w critical: $opt_c \n");
}

# verify warning is less than critical
if ( $opt_w =~ /[kMG]/) {
	unless ( $warn > $crit) {
		usage("Disk size: warning ($opt_w) should be greater than critical ($opt_c) \n");
	}
}else{
	unless ( $warn < $crit) {
		usage("Percentage: warning ($opt_w) should be less than critical ($opt_c) \n");
	}
}

my $workgroup = $1 if (defined($opt_W) && $opt_W =~ /(.*)/);

# end of options checking


my $state = "OK";
my $answer = undef;
my $res = undef;
my @lines = undef;

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub { 
	print "No Answer from Client\n";
	exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

# Execute an "ls" on the share using smbclient program
# get the results into $res
if (defined($workgroup)) {
	$res = qx/$smbclient \/\/$host\/$share $pass -W $workgroup -U $user $smbclientoptions -c ls/;
} else {
	print "$smbclient " . "\/\/$host\/$share" ." $pass -U $user $smbclientoptions -c ls\n" if ($verbose);
	$res = qx/$smbclient \/\/$host\/$share $pass -U $user $smbclientoptions -c ls/;
}
#Turn off alarm
alarm(0);

#Split $res into an array of lines
@lines = split /\n/, $res;

#Get the last line into $_
$_ = $lines[$#lines];
#print "$_\n";

#Process the last line to get free space.  
#If line does not match required regexp, return an UNKNOWN error
if (/\s*(\d*) blocks of size (\d*)\. (\d*) blocks available/) {

	my ($avail) = ($3*$2)/1024;
	my ($avail_bytes) = $avail;
	my ($capper) = int(($3/$1)*100);
	my ($mountpt) = "\\\\$host\\$share";

	#Check $warn and $crit for type (%/M/G) and set up for tests
	#P = Percent, K = KBytes
	my $warn_type;
	my $crit_type;

	if ($opt_w =~ /^([0-9]+$)/) {
		$warn_type = "P";
	} elsif ($opt_w =~ /^([0-9]+)k$/) {
		$warn_type = "K";
		$warn = $1;
	} elsif ($opt_w =~ /^([0-9]+)M$/) {
		$warn_type = "K";
		$warn = $1 * 1024;
	} elsif ($opt_w =~ /^([0-9]+)G$/) {
		$warn_type = "K";
		$warn = $1 * 1048576;
	}
	if ($opt_c =~ /^([0-9]+$)/) {
		$crit_type = "P";
	} elsif ($opt_c =~ /^([0-9]+)k$/) {
		$crit_type = "K";
		$crit = $1;
	} elsif ($opt_c =~ /^([0-9]+)M$/) {
		$crit_type = "K";
		$crit = $1 * 1024;
	} elsif ($opt_c =~ /^([0-9]+)G$/) {
		$crit_type = "K";
		$crit = $1 * 1048576;
	}

	if (int($avail / 1024) > 0) {
		$avail = int($avail / 1024);
		if (int($avail /1024) > 0) {
			$avail = (int(($avail / 1024)*100))/100;
			$avail = $avail ."G";
		} else {
			$avail = $avail ."M";
		}
	} else {
		$avail = $avail ."K";
	}

#print ":$warn:$warn_type:\n";
#print ":$crit:$crit_type:\n";
#print ":$avail:$avail_bytes:$capper:$mountpt:\n";

	if ((($warn_type eq "P") && (100 - $capper) < $warn) || (($warn_type eq "K") && ($avail_bytes > $warn))) { 
		$answer = "Disk ok - $avail ($capper%) free on $mountpt\n";
	} elsif ((($crit_type eq "P") && (100 - $capper) < $crit) || (($crit_type eq "K") && ($avail_bytes > $crit))) {
		$state = "WARNING";
		$answer = "WARNING: Only $avail ($capper%) free on $mountpt\n";
	} else {
		$state = "CRITICAL";
		$answer = "CRITICAL: Only $avail ($capper%) free on $mountpt\n";
	}
} else {
	$answer = "Result from smbclient not suitable\n";
	$state = "UNKNOWN";
	foreach (@lines) {
		if (/(Access denied|NT_STATUS_LOGON_FAILURE)/) {
			$answer = "Access Denied\n";
			$state = "CRITICAL";
			last;
		}
		if (/(Unknown host \w*|Connection.*failed)/) {
			$answer = "$1\n";
			$state = "CRITICAL";
			last;
		}
		if (/(You specified an invalid share name|NT_STATUS_BAD_NETWORK_NAME)/) {
			$answer = "Invalid share name \\\\$host\\$share\n";
			$state = "CRITICAL";
			last;
		}
	}
}


print $answer;
print "$state\n" if ($verbose);
exit $ERRORS{$state};

sub print_usage () {
	print "Usage: $PROGNAME -H <host> -s <share> -u <user> -p <password> 
      -w <warn> -c <crit> [-W <workgroup>] [-P <port>]\n";
}

sub print_help () {
	print_revision($PROGNAME,'$Revision: 1.1.1.1 $');
	print "Copyright (c) 2000 Michael Anthon/Karl DeBisschop

Perl Check SMB Disk plugin for Nagios

";
	print_usage();
	print "
-H, --hostname=HOST
   NetBIOS name of the server
-s, --share=STRING
   Share name to be tested
-W, --workgroup=STRING
   Workgroup or Domain used (Defaults to \"WORKGROUP\")
-u, --user=STRING
   Username to log in to server. (Defaults to \"guest\")
-p, --password=STRING
   Password to log in to server. (Defaults to \"guest\")
-w, --warning=INTEGER or INTEGER[kMG]
   Percent of used space at which a warning will be generated (Default: 85%)
      
-c, --critical=INTEGER or INTEGER[kMG]
   Percent of used space at which a critical will be generated (Defaults: 95%)
-P, --port=INTEGER
   Port to be used to connect to. Some Windows boxes use 139, others 445 (Defaults to smbclient default)
   
   If thresholds are followed by either a k, M, or G then check to see if that
   much disk space is available (kilobytes, Megabytes, Gigabytes)

   Warning percentage should be less than critical
   Warning (remaining) disk space should be greater than critical.

";
	support();
}
