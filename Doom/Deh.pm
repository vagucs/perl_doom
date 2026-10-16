# DOOM generic portado do python_doom para Perl com SDL2.
#
# Por Wagner Nunes da Silva
#
# vagucs@bol.com.br
# vagucs@vagucs.com.br
# vagucs@gmail.com
#
# www.vagucs.com.br
#
# Trecho DeHackEd: Thing Health, Speed e Bits, e o lump DEHACKED.

package Doom::Deh;

use strict;
use warnings;

use Doom::Defs qw(FRACUNIT);
use Doom::Info ();

sub apply_text {
    my ($text) = @_;
    return 0 if !defined $text || $text !~ /Thing|Patch File/i;
    my $thing = -1;
    my $n = 0;
    for my $line (split /\r?\n/, $text) {
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /\A#/;
        if ($line =~ /\AThing\s+(\d+)/i) {
            $thing = $1 - 1;
            next;
        }
        next if $thing < 0 || $thing > $#Doom::Info::MOBJINFO;
        my $info = $Doom::Info::MOBJINFO[$thing];
        next if !$info;
        if ($line =~ /\AHealth\s*=\s*(-?\d+)/i) {
            $info->[2] = $1 + 0;
            $n++;
        }
        elsif ($line =~ /\ASpeed\s*=\s*(-?\d+)/i) {
            my $spd = $1 + 0;
            $info->[15] = abs($spd) > 64 ? $spd : $spd * FRACUNIT;
            $n++;
        }
        elsif ($line =~ /\ABits\s*=\s*(-?\d+)/i) {
            $info->[21] = $1 + 0;
            $n++;
        }
    }
    return $n;
}

sub load_file {
    my ($path) = @_;
    return 0 if !$path || !-f $path;
    open my $fh, '<', $path or return 0;
    local $/;
    my $text = <$fh>;
    close $fh;
    my $n = apply_text($text);
    print "dehacked $path\n" if $n;
    return $n;
}

sub load_lump {
    my ($wad) = @_;
    return 0 if !$wad || $wad->check_num_for_name('DEHACKED') < 0;
    my $n = apply_text($wad->cache_lump_name('DEHACKED'));
    print "dehacked DEHACKED\n" if $n;
    return $n;
}

1;
