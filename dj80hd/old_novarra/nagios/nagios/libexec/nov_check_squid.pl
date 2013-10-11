#!/usr/local/groundwork/bin/perl -w
# First nagios plugin for squid
#
# Date         Name             Revision
# ---------------------------------------------------------
# 14-APR-2008  jwerwath         initial
# 08-OCT-2008  dchrul           Added process size metric
#
use strict;
use Getopt::Std;
use IO::Socket;

use vars qw($opt_c $opt_t $opt_h $opt_w $verb_err %exit_codes %types);

# Predefined exit codes for Nagios
%exit_codes   = ('UNKNOWN' ,-1,
		 'OK'      , 0,
                 'WARNING' , 1,
                 'CRITICAL', 2,);

%types = (0,'5min Median HTTP Response Time [s]',1,'5min average CPU Usage [%]',2,'Median DNS Response Time [s]',3,'Hit Ratio [float]',4,'Error Ratio [float]',5,'Process Size');

# Turn this to 1 to see reason for parameter errors (if any)
$verb_err     = 1;


# Get the options
if ($#ARGV le 0)
{
  &usage;
}
else
{
  getopts('h:c:t:w:');
}

# Shortcircuit the switches
if (!$opt_w or $opt_w < 0 or !$opt_c or $opt_c < 0)
{
  print "*** You must define WARN and CRITICAL levels!\n" if ($verb_err);
  &usage;
}
elsif (!defined($opt_t))
{
  print "*** You must specify a type!\n" if ($verb_err);
  &usage;
}
elsif ($opt_t < 0 || $opt_t > scalar (keys(%types)))
{
  print "*** You must specify a VALID type!\n" if ($verb_err);
  &usage;
}
elsif (!$opt_h)
{
  print "*** You must specify a squid host!\n" if ($verb_err);
  &usage;
}

#indexes in info correspond to the index passed as -t parameter
my @info = &get_squid_info($opt_h);

#Error Check
if ($opt_t != 3) # No threshold check for hit ratio
{
  if ($info[$opt_t] > $opt_c)
  {
    print "CRITICAL: " . $types{$opt_t} . " value " . $info[$opt_t] . " > " . $opt_c . "\n";
    exit $exit_codes{'CRITICAL'}; 
  }
  elsif ($info[$opt_t] > $opt_w)
  {
    print "WARNING: " . $types{$opt_t} . " value " . $info[$opt_t] . " > " . $opt_w . "\n";
    exit $exit_codes{'WARNING'}; 
  }
}

print "OK: " . $types{$opt_t} . "=" . $info[$opt_t];
#print the performance data section per nagios spec
print "|" . $opt_t . "=" . $info[$opt_t] . "\n";
exit $exit_codes{'OK'}; 

# Show usage
sub usage()
{
  print "\n$0 v1.0 - Nagios Plugin\n\n";
  print "usage:\n";
  print " $0 -h <host> -f <type> -w <warnlevel> -c <critlevel>\n\n";
  print "options:\n";
  print " -h HOST      \n";
  print " -t TYPE      0=# HTTP resp time(s), 1=CPU Usage(%), 2=DNS resp time(s)\n";
  print "              3=Hit Ratio(float), 4=Error Ratio(float), 5=Process Size\n";
  print " -w NUMBER    value above which to issue a warning (NA for type 3)\n";
  print " -c NUMBER    value above which to issue a critical (NA for type 3)\n";
  exit $exit_codes{'UNKNOWN'}; 
}

###########################################################################
# get an array of all the squid info we are interested in
# the index of the array corresponds to the 'type' number used in the
# argument list.
#
# @param $host - ip or domain name of squid box
# @returns array on success, scalar error message on failure.
#
#
# Here is a snapshot of info that we are grepping...

# Output from command   /usr/local/squid/bin/squidclient mgr:info
#
#HTTP/1.0 200 OK
#Server: squid/2.6.STABLE9-20070214
#Date: Mon, 14 Apr 2008 20:00:56 GMT
#Content-Type: text/plain
#Expires: Mon, 14 Apr 2008 20:00:56 GMT
#Last-Modified: Mon, 14 Apr 2008 20:00:56 GMT
#X-Cache: MISS from frankenstein1
#Via: 1.0 frankenstein1:3128 (squid/2.6.STABLE9-20070214)
#Proxy-Connection: close
#
#Squid Object Cache: Version 2.6.STABLE9-20070214
#Start Time:     Tue, 05 Jun 2007 22:04:17 GMT
#Current Time:   Mon, 14 Apr 2008 20:00:56 GMT
#Connection information for squid:
#        Number of clients accessing cache:      28
#        Number of HTTP requests received:       1258676944
#        Number of ICP messages received:        0
#        Number of ICP messages sent:    0
#        Number of queued ICP replies:   0
#        Request failure ratio:   0.00
#        Average HTTP requests per minute since start:   2784.5
#        Average ICP messages per minute since start:    0.0
#        Select loop called: -1466947376 times, -18.489 ms avg
#Cache information for squid:
#        Request Hit Ratios:     5min: 44.8%, 60min: 45.7%
#        Byte Hit Ratios:        5min: 37.6%, 60min: 40.0%
#        Request Memory Hit Ratios:      5min: 8.8%, 60min: 8.3%
#        Request Disk Hit Ratios:        5min: 70.5%, 60min: 70.7%
#        Storage Swap size:      414720976 KB
#        Storage Mem size:       8260 KB
#        Mean Object Size:       13.97 KB
#        Requests given to unlinkd:      211904459
#Median Service Times (seconds)  5 min    60 min:
#        HTTP Requests (All):   0.06286  0.05951
#        Cache Misses:          0.18699  0.18699
#        Cache Hits:            0.01309  0.01235
#        Near Hits:             0.16775  0.16775
#        Not-Modified Replies:  0.00091  0.00091
#        DNS Lookups:           0.00190  0.00190
#        ICP Queries:           0.00000  0.00000
#Resource usage for squid:
#        UP Time:        27122199.162 seconds
#        CPU Time:       813088.864 seconds
#        CPU Usage:      3.00%
#        CPU Usage, 5 minute avg:        6.22%
#        CPU Usage, 60 minute avg:       5.92%
#        Process Data Segment Size via sbrk(): -1335092 KB
#        Maximum Resident Size: 0 KB
#        Page faults with physical i/o: 1
#Memory usage for squid via mallinfo():
#        Total space in arena:  -1305396 KB
#        Ordinary blocks:       -1307547 KB    255 blks
#        Small blocks:               0 KB      0 blks
#        Holding blocks:         17716 KB      7 blks
#        Free Small blocks:          0 KB
#        Free Ordinary blocks:    2150 KB
#        Total in use:          -1289831 KB 100%
#        Total free:              2150 KB 0%
#        Total size:            -1287680 KB
#Memory accounted for:
#        Total accounted:       2217303 KB
#        memPoolAlloc calls: 1755987865
#        memPoolFree calls: 1666910205
#File descriptor usage for squid:
#        Maximum number of file descriptors:   8192
#        Largest file desc currently in use:    565
#        Number of file desc currently in use:  529
#        Files queued for open:                   0
#        Available number of file descriptors: 7663
#        Reserved number of file descriptors:   100
#        Store Disk files open:                   5
#        IO loop method:                     epoll
#Internal Data Structures:
#        29676755 StoreEntries
#          1711 StoreEntries with MemObjects
#          1643 Hot Object Cache Items
#        29676597 on-disk objects
###########################################################################
sub get_squid_info()
{
  my $host = shift;
  my @lines = get_squid_info_lines($host);
  #print join("-\n",@lines);
  my @values = ();
  foreach (@lines)
  {
    $values[0] = $1 if (/HTTP Requests \(All\):\s+(\S+)\s+(\S+)/);
    $values[1] = $1 if (/CPU Usage, 5 minute avg:\s+([-0-9\.]+)/i);
    $values[2] = $1 if (/DNS Lookups:\s+(\S+)\s+(\S+)/);
    $values[3] = $1 if (/Request Hit Ratios:\s+5min:\s+([^%]+)%,\s+60min:\s+([^%]+)%/);
    $values[4] = $1 if (/Request failure ratio:\s+(\S+)/);
    $values[5] = $1 if (/Process Data Segment Size via sbrk\(\):\s+(\S+)/);

    #This will be the case if squid is not configured to accept connections.
    if (/Access Denied\./)
    {
      print "Access Denied";
      exit $exit_codes{'UNKNOWN'}; 
    }
  }
  return @values;
  
} #get_squid_info()

#sub test_get_squid_info_lines()
#{
#  if (open (F,"/usr/local/groundwork/nagios/libexec/info.txt"))
#  {
#    my @lines = (<F>);
#    close F;
#    return @lines;
#  }
#  else
#  {
#      print "could not open FILE $!";
#      exit $exit_codes{'UNKNOWN'}; 
#  }
#}
###########################################################################
# Send an HTTP request to squid at $host and return the output as an
# array of output lines
#
# @param $host - ip or domain name of squid box
# @returns array on success, exits on error                      
#
###########################################################################
sub get_squid_info_lines()
{
  my $host = shift;
  my $port = 3128;
  my $http_request_buf = "GET cache_object://$host/info HTTP/1.0\n\n";
  #
  # TEST CODE _ REMOVE THIS FOR PRODUCTION
  #
  #$host = "www.scissorsoft.com";
  #$port = 80;
  #$http_request_buf = "GET /paul/info.txt HTTP/1.0\n\n";
  my $s;
  my @lines;   
  if($s = IO::Socket::INET->new(PeerAddr => $host, PeerPort => 3128, Proto => 'tcp'))
  {
    print $s $http_request_buf;
    my @lines = (<$s>);
    close($s);
    return @lines;
  }
  else
  {
    print "Could not create socket for $host $!";
    exit $exit_codes{'UNKNOWN'}; 
  }
}#get_squid_info_lines()
