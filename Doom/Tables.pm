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
# Seno, tangente e o arco do tantoangle. Igual a doom/tables.py.

package Doom::Tables;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(init_tables fine_sin fine_cos slope_div);

use Doom::Compat qw(as_u32);
use Doom::Defs qw(
    ANGLETOFINESHIFT ANG90 DBITS FINEANGLES FINEMASK FRACUNIT SLOPERANGE
);

our @FINESINE;
our @FINETANGENT;
our @TANTOANGLE;

sub init_tables {
    return if @FINESINE;
    my $n = int(FINEANGLES / 4 * 5);
    for my $i (0 .. $n - 1) {
        my $a = ($i + 0.5) * 3.141592653589793 * 2 / FINEANGLES;
        $FINESINE[$i] = int(FRACUNIT * sin($a));
    }
    my $tn = int(FINEANGLES / 2);
    for my $i (0 .. $tn - 1) {
        my $a = ($i - FINEANGLES / 4 + 0.5) * 3.141592653589793 * 2 / FINEANGLES;
        my $c = cos($a);
        my $v;
        if (abs($c) < 1e-8) {
            $v = sin($a) >= 0 ? 0x7FFFFFFF : -0x7FFFFFFF;
        }
        else {
            $v = int(FRACUNIT * sin($a) / $c);
        }
        $v = 0x7FFFFFFF if $v > 0x7FFFFFFF;
        $v = -0x7FFFFFFF if $v < -0x7FFFFFFF;
        $FINETANGENT[$i] = $v;
    }
    for my $i (0 .. SLOPERANGE) {
        $TANTOANGLE[$i] = as_u32(int(atan2($i, SLOPERANGE) / (3.141592653589793 * 2) * 4294967295));
    }
    return;
}

sub fine_sin {
    return $FINESINE[(as_u32($_[0]) >> ANGLETOFINESHIFT) & FINEMASK];
}

sub fine_cos {
    return $FINESINE[((as_u32($_[0]) >> ANGLETOFINESHIFT) + int(FINEANGLES / 4)) & FINEMASK];
}

sub slope_div {
    my ($num, $den) = @_;
    return SLOPERANGE if $den < 512;
    my $ans = int(($num << 3) / ($den >> 8));
    return $ans > SLOPERANGE ? SLOPERANGE : $ans;
}

1;
