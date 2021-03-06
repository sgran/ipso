use strict;
use warnings;
use DBD::Pg;
use Data::Dumper;
use Switch;
use Regexp::Common qw /net/;
use Regexp::Common::net::CIDR ();
use Regexp::IPv6 qw($IPv6_re);

sub dbconnect{
	my $dbname='ipso';
	my $host='localhost';
	my $port=5432;
	my $options='';
	my $username='ipso';
	my $password='ipso';
	my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",$username,$password,
		{AutoCommit => 1, RaiseError => 1, PrintError => 0}
	);
	return $dbh;
}

sub fetchrows{
	my ($dbh,$sql,$key)=@_;
	my $sth = $dbh->prepare("$sql");
	$sth->execute;
	my $tmp=$sth->fetchall_hashref($key);
	return %{$tmp};
}

sub getBlockInfo{
	my $dbh=dbconnect();
	my %ipblocks=fetchrows($dbh,'SELECT blockid,ipblock,ipblockfamily,note,EXTRACT(EPOCH FROM now()-changed) as age FROM ipblocks',1);
	foreach my $record (keys %ipblocks){
		my ($block,$mask)=split/\//,$ipblocks{$record}{ipblock};
		switch ($ipblocks{$record}{ipblockfamily}) {
			case 4 { $ipblocks{$record}{maxips}=2**(32-$mask);  }
			case 6 { $ipblocks{$record}{maxips}=2**(128-$mask); }
		}
	}
	my %ipallocations=fetchrows($dbh,'SELECT ipblocks.blockid,COUNT(ipcount) AS allocations,SUM(ipcount) AS allocated FROM ipblocks,ipallocations WHERE ipblocks.blockid=ipallocations.blockid GROUP BY ipblocks.blockid',1);
	foreach my $record (keys %ipallocations){
		my $blockid=$ipallocations{$record}{blockid};
		$ipblocks{$blockid}{allocations}=$ipallocations{$record}{allocations};
		$ipblocks{$blockid}{allocated}=$ipallocations{$record}{allocated};
	}
	$dbh->disconnect;
	return %ipblocks;
}

sub addIPBlock{
	my ($newblock,$note)=@_;
	my $dbh=dbconnect();
	my %overlap=fetchrows($dbh,"SELECT ipblock FROM ipblocks WHERE '$newblock' <<= ipblock OR '$newblock' >>= ipblock",1);
	my @overlaps=();
	foreach my $ipblock (keys %overlap){
		push @overlaps,$ipblock;
	}
	my $overlapcount=scalar @overlaps;
	if ($overlapcount>0){
		print "Error: IP block $newblock overlaps $overlapcount existing IP block";
		if ($overlapcount>1){
			print "s";
		}
		print ": " . join (", ",@overlaps) . "\n";
		exit;
	}
	$dbh->do("INSERT INTO ipblocks (ipblock,note) VALUES ('$newblock','$note')");
	$dbh->disconnect;
	print "Block added.\n";
}

sub getAllocationInfo{
	my %allocinfo=();
	my $block=shift;
	my $sql='SELECT allocid,ipblock,ipblockfamily,firstip,lastip,ipcount,used,note FROM ipblock_allocations';
	if (is_ipv4_cidr($block) || is_ipv6_cidr($block)){
		$sql.=" WHERE ipblock = '$block'";
	} elsif ($block ne 'all'){
		$sql.=" WHERE blockid = '$block'";
	}
	my $dbh=dbconnect();
	my %allocations=fetchrows($dbh,$sql,1);
	$dbh->disconnect;
	if (scalar keys %allocations == 0){
		print "No allocations found.\n";
		exit;
	}
	return %allocations;
}

sub is_ipv4_address{
	my $ip=shift;
	if ($ip =~ $RE{net}{IPv4}){
		return 1;
	} else {
		return 0;
	}
}

sub is_ipv4_cidr{
	my $cidr=shift;
	if ($cidr =~ $RE{net}{CIDR}{IPv4}){
		return 1;
	} else {
		return 0;
	}
}

sub is_ipv6_address{
	my $ip=shift;
	if ($ip =~ $RE{net}{IPv6}){
		return 1;
	} else {
		return 0;
	}
}

# This regex taken from
# http://blog.markhatton.co.uk/2011/03/15/regular-expressions-for-ip-addresses-cidr-ranges-and-hostnames/
sub is_ipv6_cidr{
	my $cidr=shift;
	if ($cidr =~ /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*(\/(\d|\d\d|1[0-1]\d|12[0-8]))$/){
		return 1;
	} else {
		return 0;
	}
}

1;
