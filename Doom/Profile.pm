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
# Tempos opcionais do quadro. Fica desligado, a menos que o jogo
# receba -profile. A saida e uma media, nao um numero por quadro.

package Doom::Profile;

use strict;
use warnings;

use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

our $ON = 0;

my %all;
my %win;
my $frames = 0;
my $win_frames = 0;
my $win_t = 0;
my $start = 0;

sub now {
    return clock_gettime(CLOCK_MONOTONIC);
}

sub add {
    my ($slot, $dt) = @_;
    return if !$ON;
    $all{$slot} += $dt;
    $win{$slot} += $dt;
    return;
}

sub frame {
    return if !$ON;
    my $now = now();
    $start = $win_t = $now if !$start;
    $frames++;
    $win_frames++;
    return if $now - $win_t < 2;
    _show('janela', $win_frames, $now - $win_t, \%win);
    %win = ();
    $win_frames = 0;
    $win_t = $now;
    return;
}

sub finish {
    return if !$ON || !$frames;
    my $span = now() - $start;
    $span = 0.001 if $span <= 0;
    _show('total', $frames, $span, \%all);
    $ON = 0;
    return;
}

sub _show {
    my ($title, $n, $span, $acc) = @_;
    return if $n <= 0;
    my $render = $acc->{render} || 0;
    my $upload = $acc->{upload} || 0;
    my $present = $acc->{present} || 0;
    my $sum = $render + $upload + $present;
    $sum = 0.001 if $sum <= 0;
    my $line = sub {
        my ($name, $sec) = @_;
        printf "  %-8s %5.1f%%  %6.2f ms\n", $name, 100 * $sec / $sum, 1000 * $sec / $n;
    };
    printf "perfil %s  %.1f s  %d quadros\n", $title, $span, $n;
    $line->('render', $render);
    $line->('upload', $upload);
    $line->('present', $present);
    my $column = $acc->{column} || 0;
    my $planes = $acc->{planes} || 0;
    my $base = $render > 0 ? $render : 0.001;
    printf "  coluna   %5.1f%% do render  %6.2f ms\n", 100 * $column / $base, 1000 * $column / $n;
    printf "  planos   %5.1f%% do render  %6.2f ms\n", 100 * $planes / $base, 1000 * $planes / $n;
    print "  coluna e planos estao dentro do render; o ceu entra nos dois\n";
    return;
}

END { finish(); }

1;
