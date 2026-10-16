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
# Vida, municao, armadura, chave e espingarda saem do chao.
# Igual a doom/mobj.py no toque.

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
    elsif ($kind == 2008 || $kind == 2049) {
        $taken = _shells($mo, $kind == 2008 ? 4 : 20);
        print($kind == 2008 ? "pegou cartuchos\n" : "pegou uma caixa de cartuchos\n") if $taken;
    }
    elsif ($kind == 2001) {
        $taken = _give_shotgun($mo);
    }
    elsif ($kind == 2002) {
        $taken = _give_chaingun($mo);
    }
    elsif ($kind == 2003) {
        $taken = _give_rocket($mo);
    }
    elsif ($kind == 2010) {
        $taken = _rockets($mo, 1);
        print "pegou um foguete\n" if $taken;
    }
    elsif ($kind == 2046) {
        $taken = _rockets($mo, 5);
        print "pegou uma caixa de foguetes\n" if $taken;
    }
    elsif ($kind == 2004) {
        $taken = _give_plasma($mo);
    }
    elsif ($kind == 2006) {
        $taken = _give_bfg($mo);
    }
    elsif ($kind == 2005) {
        $taken = _give_chainsaw($mo);
    }
    elsif ($kind == 82) {
        $taken = _give_ssg($mo);
    }
    elsif ($kind == 2047) {
        $taken = _cells($mo, 20);
        print "pegou uma celula\n" if $taken;
    }
    elsif ($kind == 17) {
        $taken = _cells($mo, 100);
        print "pegou um pacote de celulas\n" if $taken;
    }
    elsif ($kind == 2022) {
        $taken = _timed($mo, 'pow_invul', 30 * 35);
        print "invulneravel\n" if $taken;
    }
    elsif ($kind == 2023) {
        $taken = _berserk($mo);
    }
    elsif ($kind == 2024) {
        $taken = _timed($mo, 'pow_invis', 60 * 35);
        print "invisivel\n" if $taken;
    }
    elsif ($kind == 2025) {
        $taken = _timed($mo, 'pow_suit', 60 * 35);
        print "traje contra radiacao\n" if $taken;
    }
    elsif ($kind == 2026) {
        $taken = _map_power($mo);
    }
    elsif ($kind == 2045) {
        $taken = _timed($mo, 'pow_lite', 120 * 35);
        print "visor de luz\n" if $taken;
    }
    elsif ($kind == 8) {
        $mo->{maxammo} = ($mo->{maxammo} || 200) * 2 if ($mo->{maxammo} || 200) < 400;
        $mo->{maxshells} = ($mo->{maxshells} || 50) * 2 if ($mo->{maxshells} || 50) < 100;
        $mo->{maxrockets} = ($mo->{maxrockets} || 50) * 2 if ($mo->{maxrockets} || 50) < 100;
        $mo->{maxcells} = ($mo->{maxcells} || 300) * 2 if ($mo->{maxcells} || 300) < 600;
        _bullets($mo, 10);
        $mo->{shells} = ($mo->{shells} || 0) + 4;
        $mo->{shells} = $mo->{maxshells} if $mo->{shells} > ($mo->{maxshells} || 50);
        $mo->{rockets} = ($mo->{rockets} || 0) + 1;
        $mo->{rockets} = $mo->{maxrockets} if $mo->{rockets} > ($mo->{maxrockets} || 50);
        $mo->{cells} = ($mo->{cells} || 0) + 20;
        $mo->{cells} = $mo->{maxcells} if $mo->{cells} > ($mo->{maxcells} || 300);
        $taken = 1;
        $mo->{message} = 'pegou a mochila';
        $mo->{messaget} = 140;
        print "pegou a mochila\n";
    }
    return 0 if !$taken;
    $mo->{items} = ($mo->{items} || 0) + 1 if ($item->{flags} || 0) & 0x800000;
    $mo->{bonuscount} = ($mo->{bonuscount} || 0) + 6;
    my $power = $kind == 2022 || $kind == 2023 || $kind == 2024 || $kind == 2025 || $kind == 2026 || $kind == 2045;
    my $gun = $kind == 2001 || $kind == 2002 || $kind == 2003 || $kind == 2004 || $kind == 2005 || $kind == 2006 || $kind == 82;
    Doom::Sound::at($world, $power ? 'getpow' : $gun ? 'wpnup' : 'itemup');
    if (!$mo->{message}) {
        $mo->{message} = 'pegou';
        $mo->{messaget} = 140;
    }
    Doom::Attack::_remove($world, $item);
    return 1;
}

sub _timed {
    my ($mo, $key, $tics) = @_;
    $mo->{$key} = $tics;
    Doom::Cheat::sync_flags($mo);
    return 1;
}

sub _map_power {
    my ($mo) = @_;
    return 0 if $mo->{pow_map};
    $mo->{pow_map} = 1;
    print "mapa do computador\n";
    return 1;
}

sub _berserk {
    my ($mo) = @_;
    my $hp = $mo->{health} || 0;
    if ($hp < 100) {
        $hp += 100;
        $hp = 100 if $hp > 100;
        $mo->{health} = $hp;
        print "vida $hp\n";
    }
    $mo->{pow_berserk} = 1;
    print "berserk\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'fist';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'fist');
    }
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

sub _shells {
    my ($mo, $n) = @_;
    my $max = $mo->{maxshells} || 50;
    my $have = $mo->{shells} || 0;
    return 0 if $have >= $max;
    $have += $n;
    $have = $max if $have > $max;
    $mo->{shells} = $have;
    print "cartuchos $have\n";
    return 1;
}

sub _give_shotgun {
    my ($mo) = @_;
    my $full = ($mo->{shells} || 0) >= ($mo->{maxshells} || 50);
    return 0 if $mo->{owns_shotgun} && $full;
    $mo->{owns_shotgun} = 1;
    _shells($mo, 8);
    print "pegou a espingarda\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'shotgun';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'shotgun');
    }
    return 1;
}

sub _rockets {
    my ($mo, $n) = @_;
    my $max = $mo->{maxrockets} || 50;
    my $have = $mo->{rockets} || 0;
    return 0 if $have >= $max;
    $have += $n;
    $have = $max if $have > $max;
    $mo->{rockets} = $have;
    print "foguetes $have\n";
    return 1;
}

sub _cells {
    my ($mo, $n) = @_;
    my $max = $mo->{maxcells} || 300;
    my $have = $mo->{cells} || 0;
    return 0 if $have >= $max;
    $have += $n;
    $have = $max if $have > $max;
    $mo->{cells} = $have;
    print "celulas $have\n";
    return 1;
}

sub _give_chainsaw {
    my ($mo) = @_;
    return 0 if $mo->{owns_chainsaw};
    $mo->{owns_chainsaw} = 1;
    print "pegou a serra\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'chainsaw';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'chainsaw');
    }
    return 1;
}

sub _give_ssg {
    my ($mo) = @_;
    my $full = ($mo->{shells} || 0) >= ($mo->{maxshells} || 50);
    return 0 if $mo->{owns_ssg} && $full;
    $mo->{owns_ssg} = 1;
    _shells($mo, 8);
    print "pegou a super espingarda\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'ssg';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'ssg');
    }
    return 1;
}

sub _give_bfg {
    my ($mo) = @_;
    my $full = ($mo->{cells} || 0) >= ($mo->{maxcells} || 300);
    return 0 if $mo->{owns_bfg} && $full;
    $mo->{owns_bfg} = 1;
    _cells($mo, 40);
    print "pegou a bfg\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'bfg';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'bfg');
    }
    return 1;
}

sub _give_plasma {
    my ($mo) = @_;
    my $full = ($mo->{cells} || 0) >= ($mo->{maxcells} || 300);
    return 0 if $mo->{owns_plasma} && $full;
    $mo->{owns_plasma} = 1;
    _cells($mo, 20);
    print "pegou o rifle de plasma\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'plasma';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'plasma');
    }
    return 1;
}

sub _give_rocket {
    my ($mo) = @_;
    my $full = ($mo->{rockets} || 0) >= ($mo->{maxrockets} || 50);
    return 0 if $mo->{owns_rocket} && $full;
    $mo->{owns_rocket} = 1;
    _rockets($mo, 2);
    print "pegou o lanca-foguetes\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'rocket';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'rocket');
    }
    return 1;
}

sub _give_chaingun {
    my ($mo) = @_;
    my $full = ($mo->{ammo} || 0) >= ($mo->{maxammo} || 200);
    return 0 if $mo->{owns_chaingun} && $full;
    $mo->{owns_chaingun} = 1;
    _bullets($mo, 10);
    print "pegou a metralhadora\n";
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{wantgun} = 'chaingun';
    }
    else {
        Doom::Attack::switch_weapon($mo, 'chaingun');
    }
    return 1;
}

1;
