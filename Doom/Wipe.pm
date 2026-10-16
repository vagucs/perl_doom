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
# Derretimento da tela. Igual a doom/wipe.py.

package Doom::Wipe;

use strict;
use warnings;

use Doom::Defs qw(SCREENWIDTH SCREENHEIGHT);

sub new {
    my ($class) = @_;
    return bless { active => 0, y => [], start => '', end => '' }, $class;
}

sub _pairs {
    my ($pic) = @_;
    my $need = SCREENWIDTH * SCREENHEIGHT;
    $pic .= "\0" x ($need - length($pic)) if length($pic) < $need;
    return [unpack('n*', substr($pic, 0, $need))];
}

sub capture_start {
    my ($self, $fb) = @_;
    my $need = SCREENWIDTH * SCREENHEIGHT;
    $fb .= "\0" x ($need - length($fb)) if length($fb) < $need;
    $self->{start} = substr($fb, 0, $need);
    $self->{sp} = _pairs($self->{start});
    return;
}

sub capture_end {
    my ($self, $fb) = @_;
    my $need = SCREENWIDTH * SCREENHEIGHT;
    $fb .= "\0" x ($need - length($fb)) if length($fb) < $need;
    $self->{end} = substr($fb, 0, $need);
    $self->{ep} = _pairs($self->{end});
    return;
}

sub begin {
    my ($self, $fb) = @_;
    $$fb = $self->{start};
    my $cols = int(SCREENWIDTH / 2);
    my @y = (0) x $cols;
    $y[0] = -int(rand(16));
    for my $i (1 .. $cols - 1) {
        my $next = $y[$i - 1] + int(rand(3)) - 1;
        $y[$i] = $next > 0 ? 0 : ($next == -16 ? -15 : $next);
    }
    $self->{y} = \@y;
    $self->{active} = 1;
    return;
}

sub _paint {
    my ($self, $fb) = @_;
    my $h = SCREENHEIGHT;
    my $cols = int(SCREENWIDTH / 2);
    my $s = $self->{sp};
    my $e = $self->{ep};
    my $ys = $self->{y};
    my @out = (0) x ($h * $cols);
    for my $i (0 .. $#$ys) {
        my $yi = $ys->[$i];
        if ($yi <= 0) {
            for my $row (0 .. $h - 1) {
                $out[$row * $cols + $i] = $s->[$row * $cols + $i];
            }
        }
        elsif ($yi >= $h) {
            for my $row (0 .. $h - 1) {
                $out[$row * $cols + $i] = $e->[$row * $cols + $i];
            }
        }
        else {
            for my $row (0 .. $yi - 1) {
                $out[$row * $cols + $i] = $e->[$row * $cols + $i];
            }
            my $tail = $h - $yi;
            for my $row (0 .. $tail - 1) {
                $out[($yi + $row) * $cols + $i] = $s->[$row * $cols + $i];
            }
        }
    }
    $$fb = pack('n*', @out);
    return;
}

sub tick {
    my ($self, $tics, $fb) = @_;
    $tics = 1 if !$tics || $tics < 1;
    my $h = SCREENHEIGHT;
    my $done = 1;
    for (1 .. $tics) {
        $done = 1;
        for my $i (0 .. $#{$self->{y}}) {
            my $yi = $self->{y}[$i];
            if ($yi < 0) {
                $self->{y}[$i] = $yi + 1;
                $done = 0;
                next;
            }
            next if $yi >= $h;
            my $dy = $yi < 16 ? $yi + 1 : 8;
            $dy = $h - $yi if $yi + $dy > $h;
            $self->{y}[$i] = $yi + $dy;
            $done = 0;
        }
    }
    if ($done) {
        $$fb = $self->{end};
        $self->{active} = 0;
        return 1;
    }
    _paint($self, $fb);
    return 0;
}

1;
