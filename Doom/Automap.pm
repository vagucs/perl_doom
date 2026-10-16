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
# O mapa do Tab segue o jogador. Igual a doom/am_map.py nas paredes vistas.

package Doom::Automap;

use strict;
use warnings;

use Doom::Defs qw(ML_MAPPED);

use constant MAPW => 320;
use constant MAPH => 168;
use constant REDS => 176;
use constant BROWNS => 64;
use constant YELLOWS => 231;
use constant WHITE => 209;
use constant ML_SECRET => 32;
use constant ML_DONTDRAW => 128;

sub new {
    my ($class) = @_;
    return bless { active => 0, units => 8 }, $class;
}

sub toggle {
    my ($self) = @_;
    $self->{active} = $self->{active} ? 0 : 1;
    return;
}

sub cycle_cheat {
    my ($self) = @_;
    return if !$self->{active};
    $self->{cheat} = (($self->{cheat} || 0) + 1) % 2;
    return $self->{cheat};
}

sub zoom_in {
    my ($self) = @_;
    my $u = int($self->{units} * 2 / 3);
    $self->{units} = $u < 2 ? 2 : $u;
    return;
}

sub zoom_out {
    my ($self) = @_;
    my $u = int($self->{units} * 3 / 2);
    $self->{units} = $u > 64 ? 64 : $u;
    return;
}

sub draw {
    my ($self, $fb, $mo, $world) = @_;
    return if !$self->{active} || !$mo || !$world;
    my $px = $mo->{x} || 0;
    my $py = $mo->{y} || 0;
    my $all = ($self->{cheat} || 0) || (($mo->{pow_map} || 0) > 0);
    for my $ln (@{$world->{lines} || []}) {
        next if !$all && !(($ln->{flags} || 0) & ML_MAPPED);
        next if !$all && (($ln->{flags} || 0) & ML_DONTDRAW);
        my $color = _color($ln);
        next if !defined $color;
        my $v1 = $ln->{v1};
        my $v2 = $ln->{v2};
        next if !$v1 || !$v2;
        my ($x1, $y1) = $self->_xy($v1->{x}, $v1->{y}, $px, $py);
        my ($x2, $y2) = $self->_xy($v2->{x}, $v2->{y}, $px, $py);
        _line($fb, $x1, $y1, $x2, $y2, $color);
    }
    _arrow($fb, $mo);
    return;
}

sub _color {
    my ($ln) = @_;
    return REDS if !$ln->{backsector};
    return if !$ln->{frontsector};
    return REDS + 8 if ($ln->{special} || 0) == 39;
    return REDS if ($ln->{flags} || 0) & ML_SECRET;
    my $front = $ln->{frontsector};
    my $back = $ln->{backsector};
    return BROWNS if ($back->{floorheight} || 0) != ($front->{floorheight} || 0);
    return YELLOWS if ($back->{ceilingheight} || 0) != ($front->{ceilingheight} || 0);
    return;
}

sub _xy {
    my ($self, $x, $y, $px, $py) = @_;
    my $u = $self->{units} * 65536;
    $u = 65536 if $u < 65536;
    my $sx = 160 + int((($x || 0) - $px) / $u);
    my $sy = 84 - int((($y || 0) - $py) / $u);
    return ($sx, $sy);
}

sub _arrow {
    my ($fb, $mo) = @_;
    my $ang = $mo->{angle} || 0;
    my $cs = Doom::Tables::fine_cos($ang);
    my $sn = Doom::Tables::fine_sin($ang);
    my $rot = sub {
        my ($x, $y) = @_;
        my $rx = int(($x * $cs - $y * $sn) / 65536);
        my $ry = int(($x * $sn + $y * $cs) / 65536);
        return (160 + $rx, 84 - $ry);
    };
    my ($tx, $ty) = $rot->(12, 0);
    my ($lx, $ly) = $rot->(-6, 5);
    my ($rx, $ry) = $rot->(-6, -5);
    _line($fb, $tx, $ty, $lx, $ly, WHITE);
    _line($fb, $tx, $ty, $rx, $ry, WHITE);
    _line($fb, $lx, $ly, $rx, $ry, WHITE);
    return;
}

sub _plot {
    my ($fb, $x, $y, $c) = @_;
    return if $x < 0 || $x >= MAPW || $y < 0 || $y >= MAPH;
    substr($$fb, $y * MAPW + $x, 1) = chr($c & 255);
    return;
}

sub _line {
    my ($fb, $x0, $y0, $x1, $y1, $c) = @_;
    my $dx = abs($x1 - $x0);
    my $dy = -abs($y1 - $y0);
    my $sx = $x0 < $x1 ? 1 : -1;
    my $sy = $y0 < $y1 ? 1 : -1;
    my $err = $dx + $dy;
    my $guard = 0;
    while ($guard++ < 900) {
        _plot($fb, $x0, $y0, $c);
        last if $x0 == $x1 && $y0 == $y1;
        my $e2 = 2 * $err;
        if ($e2 >= $dy) {
            $err += $dy;
            $x0 += $sx;
        }
        if ($e2 <= $dx) {
            $err += $dx;
            $y0 += $sy;
        }
    }
    return;
}

1;
