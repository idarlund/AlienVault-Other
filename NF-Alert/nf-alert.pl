#!/usr/bin/perl
# NF-Alert
# Makes events for network traffic
use DateTime;
use Getopt::Std;
use Sys::Syslog;
#
use vars qw/ %opt /;

###########################################User Config Stuff

#You may want to extend this directory lower to a specific collector.  You probably don't want to run this against netflow from perimeter for instance
my $nfdir = '/var/cache/nfdump/flows/live';
#Nfdump notation: 25 Megs
my $min_session_size = '+25M'; #in-line with alert hash below
#Alert Thresholds
my %alerts = { 25 => (1, 'Network %s greater than 25M'), 100 => (2, 'Network %s greater than 100M') };
my @types = ('Download' , 'Upload');
#Polling Interval - Copy of Watchdog in minutes
my $pi = 3;
#For plugin generation
my $plugin_id = 90012;
my $plugin_name = 'NF-Alert';
my $plugin_desc = 'Netflow Alerts';


############################################End User Config
#Command Line Switches
$Getopt::Std::STANDARD_HELP_VERSION = 1;
getopts('spvc', \%opt);
#Using debug?
my $debug = defined($opt{'v'});

if ($opt{'s'}) {
	#Time to make the donuts
	make_sql();
	exit;
}

#Grab networks in use
my $networks = `grep networks= /etc/ossim/ossim_setup.conf`;
chomp($networks);
my ($net) = (split /=/, $networks)[1];
my @netblocks = split /,/, $net;

#Create filters for nfdump
my $dst_filter = join(' or dst net ', @netblocks);
my $src_filter = join(' or src net ', @netblocks);

#Debug
print "DST: $dst_filter \nSRC: $src_filter \n" if $debug;

#Make a polling date for nfdump to check
my $nfdump_check_time = DateTime->now(time_zone=> "local")->subtract( minutes => $pi)->strftime("%Y/%m/%d.%H:%M:%S");
my $nfdump_check_now = DateTime->now(time_zone=> "local")->strftime("%Y/%m/%d.%H:%M:%S");

my $nf_dump_cmd_download = "/usr/bin/nfdump -R '$nfdir' -t '$nfdump_check_time-$nfdump_check_now' -L '$min_session_size' -q -n 100 -o extended -s record/bytes '(dst net $dst_filter) and not (src net $src_filter)'";
my $nf_dump_cmd_upload = "/usr/bin/nfdump -R '$nfdir' -t '$nfdump_check_time-$nfdump_check_now' -L '$min_session_size' -q -n 100 -o extended -s record/bytes '(src net $src_filter) and not (dst net $dst_filter)'";

print "Download Command: '$nf_dump_cmd_download'\n" if $debug;
print "Upload Command: '$nf_dump_cmd_upload'\n" if $debug;

print "Download: " . `$nf_dump_cmd_download` . "\n" if $debug;
print "Upload: " . `$nf_dump_cmd_upload` . "\n" if $debug;

foreach my $type (@types) {
	print $type;
}

sub send_message {
	my $log = shift;
	#send log message, changing IPs if needed....
	openlog($plugin_name, '', 'lpr');    # don't forget this
	syslog("debug", $log);
	closelog();
}

sub make_sql () {
	my $sql_out = "INSERT INTO `plugin_sid` (`plugin_id`,`sid`,`reliability`, `priority`, `name`) VALUES ($plugin_id, %s, %s, $pri, '%s');\n";
	#Print Header
	print "DELETE FROM plugin WHERE id = '$plugin_id';\n";
	print "DELETE FROM plugin_sid where plugin_id = '$plugin_id';\n";
	print "INSERT IGNORE INTO software_cpe VALUES ('cpe:/h:$plugin_name:$plugin_name:-', '$plugin_name', '1.0' , '$plugin_name $plugin_name 1.0', '$plugin_name', '$plugin_name:$plugin_id');\n";
	print "INSERT IGNORE INTO plugin (id, type, name, description,product_type,vendor) VALUES ($plugin_id, 1, '$plugin_name', '$plugin_desc',17,'AlienVault');\n";
	foreach my $type (@types) {
		foreach my $key (keys %alerts) {
			printf "$type $key\n";
		}
	}
}

sub HELP_MESSAGE { print " -s Make the SQL for plugin: $0 -s | ossim-db\n -p Make the plugin: $0 -p > /etc/ossim/agent/plugins/$plugin_name.cfg\n -c Do the Check\n -v Be Verbose\n"; }
sub VERSION_MESSAGE { print "NF-Alerty to SIEM\n"; }

#/usr/bin/nfdump -R '/var/cache/nfdump/flows/live' -t '2014/07/26.15:17:00-2014/07/26.15:20:00' -o extended -s record/bytes '(dst net 192.168.0.0/16 or dst net 172.16.0.0/12 or dst net 10.0.0/8) and not (src net 192.168.0.0/16 or src net 172.16.0.0/12 or src net 10.0.0/8)' -L '+25M' -n 75
#2014-07-26 15:14:02.114   106.609 TCP        199.96.57.7:443   ->   192.168.100.75:54556 .AP.SF 184    20117   30.2 M      188    2.3 M   1499     1


