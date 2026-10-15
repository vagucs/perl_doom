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
# V_DrawPatch no framebuffer de 320x200. Igual a doom/v_video.py.

package Doom::VVideo;

use strict;
use warnings;

use Doom::Defs qw(SCREENWIDTH SCREENHEIGHT);

use Exporter qw(import);
our @EXPORT_OK = qw(fill draw_patch);

sub fill {
    my ($fb, $color) = @_;
    $color //= 0;
    $$fb = chr($color & 0xFF) x (SCREENWIDTH * SCREENHEIGHT);
    return;
}

sub draw_patch {
    my ($fb, $x, $y, $patch) = @_;
    return if !defined $patch || length($patch) < 8;
    my ($w, $left, $top) = unpack('s<x2s<s<', $patch);
    $x -= $left;
    $y -= $top;
    my $desttop = $y * SCREENWIDTH + $x;
    my $limit = SCREENWIDTH * SCREENHEIGHT;
    for my $col (0 .. $w - 1) {
        my $column = unpack('V', substr($patch, 8 + $col * 4, 4));
        while ($column + 1 < length($patch)) {
            my $topdelta = ord(substr($patch, $column, 1));
            last if $topdelta == 0xFF;
            my $length = ord(substr($patch, $column + 1, 1));
            my $source = $column + 3;
            my $dest = $desttop + $topdelta * SCREENWIDTH;
            for (1 .. $length) {
                if ($dest >= 0 && $dest < $limit && $source < length($patch)) {
                    substr($$fb, $dest, 1) = substr($patch, $source, 1);
                }
                $source++;
                $dest += SCREENWIDTH;
            }
            $column += $length + 4;
        }
        $desttop++;
    }
    return;
}

1;
