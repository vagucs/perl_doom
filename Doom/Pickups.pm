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
# Vida, municao, armadura e chave saem do chao.
# A pistola continua a unica arma. Igual a doom/mobj.py no toque.

package Doom::Pickups;

use strict;
use warnings;

my %KEY = (
    5  => [0, 'pegou a chave azul'],
    6  => [1, 'pegou a chave amarela'],
    13 => [2, 'pegou a chave vermelha'],
    40 => [3, 'pegou o cranio azul'],
    39 => [4, 'pegou o cranio amarelo'],
    38 => [5, 'pegou o cranio vermelho'],
);

sub touch {
    my ($world, $item, $mo) = @_;
    return 0 if !$item || !$mo || !$mo->{player} || !$item->{alive};
    my $kind = $item->{doomednum} || 0;
    my $taken = 0;
    if ($kind == 2011 || $kind == 2012) {
        my $add = $kind == 2011 ? 10 : 25;
        $taken = _heal($mo, $add, 100);
        print($kind == 2011 ? "pegou um estimulante\n" : "pegou um kit medico\n") if $taken;
    }
    elsif ($kind == 2014) {
        $taken = _heal($mo, 1, 200);
        print "pegou um bonus de vida\n" if $taken;
    }
    elsif ($kind == 2015) {
        $taken = _armor_bonus($mo);
        print "pegou um bonus de armadura\n" if $taken;
    }
    elsif ($kind == 2018 || $kind == 2019) {
        my $pts = $kind == 2018 ? 100 : 200;
        my $type = $kind == 2018 ? 1 : 2;
        if (($mo->{armorpoints} || 0) < $pts) {
            $mo->{armorpoints} = $pts;
            $mo->{armortype} = $type;
            $taken = 1;
            print($kind == 2018 ? "pegou a armadura\n" : "pegou a mega armadura\n");
            print "armadura $mo->{armorpoints}\n";
        }
    }
    elsif ($kind == 2013) {
        $taken = _heal($mo, 100, 200);
        print "super carga\n" if $taken;
    }
    elsif ($kind == 83) {
        $mo->{health} = 200;
        $mo->{armorpoints} = 200;
        $mo->{armortype} = 2;
        $taken = 1;
        print "mega esfera\n";
        print "vida 200\n";
    }
    elsif ($KEY{$kind}) {
        my ($slot, $msg) = @{$KEY{$kind}};
        $mo->{cards} ||= [(0) x 6];
        $mo->{cards}[$slot] = 1;
        $taken = 1;
        print "$msg\n";
    }
    elsif ($kind == 2007 || $kind == 2048) {
        $taken = _bullets($mo, $kind == 2007 ? 10 : 50);
        print($kind == 2007 ? "pegou um pente\n" : "pegou uma caixa de balas\n") if $taken;
    }
    elsif ($kind == 8) {
        my $max = $mo->{maxammo} || 200;
        $mo->{maxammo} = $max * 2 if $max < 400;
        _bullets($mo, 10);
        $taken = 1;
        print "pegou a mochila\n";
    }
    return 0 if !$taken;
    Doom::Attack::_remove($world, $item);
    return 1;
}

sub _heal {
    my ($mo, $add, $cap) = @_;
    my $hp = $mo->{health} || 0;
    return 0 if $hp >= $cap;
    $hp += $add;
    $hp = $cap if $hp > $cap;
    $mo->{health} = $hp;
    print "vida $hp\n";
    return 1;
}

sub _armor_bonus {
    my ($mo) = @_;
    my $pts = $mo->{armorpoints} || 0;
    return 0 if $pts >= 200;
    $pts += 1;
    $pts = 200 if $pts > 200;
    $mo->{armorpoints} = $pts;
    $mo->{armortype} = 1 if !$mo->{armortype};
    print "armadura $pts\n";
    return 1;
}

sub _bullets {
    my ($mo, $n) = @_;
    my $max = $mo->{maxammo} || 200;
    my $have = $mo->{ammo} || 0;
    return 0 if $have >= $max;
    $have += $n;
    $have = $max if $have > $max;
    $mo->{ammo} = $have;
    print "balas $have\n";
    return 1;
}

1;
