use warnings;
use strict;

#This script reads from the file containing the data from 

my $filename = 'gs12170_config.txt';

open(FH, '<', $filename) or die $!;

my $i;
$i=0;
my @addr=[];
my @data=[];


while(<FH>){
    my @words = split ' ', $_;
    $addr[$i] = hex($words[0]);
    $data[$i] = hex($words[1]);
    $i=$i+1;
}

#print "\n@addr\n";
#print "@data\n";

close(FH);


my $def = chr($addr[0]>>8);
my $chef = chr($addr[0] & 0xff);

#print "$def\n";
#print "$chef\n";

$i=0;
foreach (@addr){
    print "$addr[$i]\n";
    print "$data[$i]\n";
    $i=$i+1;
}