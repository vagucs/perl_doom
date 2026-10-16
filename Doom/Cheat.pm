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
# Cheats da fase. Igual a doom/game.py no iddqd, idkfa e idclev.

package Doom::Cheat;

use strict;
use warnings;

use Doom::Attack ();

use constant GOD    => 1;
use constant NOCLIP => 2;
use constant SHADOW => 0x40000;
use constant CLIPF  => 0x1000;
use constant POWER  => 30 * 35;

my @CODE = (
    ['idbeholdv', 'bv'],
    ['idbeholds', 'bs'],
    ['idbeholdi', 'bi'],
    ['idbeholdr', 'br'],
    ['idbeholda', 'ba'],
    ['idbeholdl', 'bl'],
    ['idchoppers', 'chop'],
    ['idspispopd', 'clip'],
    ['idkfa', 'kfa'],
    ['iddqd', 'god'],
    ['idclip', 'clip'],
    ['idfa', 'fa'],
    ['idbehold', 'behold'],
    ['iddt', 'dt'],
);

sub new {
    my ($class) = @_;
    return bless { buf => '' }, $class;
}

sub feed {
    my ($self, $key, $skill) = @_;
    return if !$key || $key < 48 || $key > 122;
    my $ch = lc chr($key);
    return if $ch !~ /[a-z0-9]/;
    $self->{buf} = substr(($self->{buf} || '') . $ch, -32);
    my ($act, $arg) = ('', '');
    if ($self->{buf} =~ /idclev(\d\d)\z/) {
        ($act, $arg) = ('clev', $1);
    }
    elsif ($self->{buf} =~ /idmus(\d\d)\z/) {
        ($act, $arg) = ('mus', $1);
    }
    else {
        for my $row (@CODE) {
            if (substr($self->{buf}, -length($row->[0])) eq $row->[0]) {
                ($act, $arg) = ($row->[1], '');
                last;
            }
        }
    }
    return if !$act;
    $self->{buf} = '';
    return if ($skill || 0) >= 4 && $act ne 'clev' && $act ne 'dt';
    return { act => $act, arg => $arg };
}

sub apply {
    my ($mo, $hit) = @_;
    return if !$mo || !$hit;
    my $act = $hit->{act} || '';
    if ($act eq 'god') {
        $mo->{cheats} = ($mo->{cheats} || 0) ^ GOD;
        if ($mo->{cheats} & GOD) {
            $mo->{health} = 100;
            print "deus ligado\n";
        }
        else {
            print "deus desligado\n";
        }
    }
    elsif ($act eq 'kfa' || $act eq 'fa') {
        _arsenal($mo, $act eq 'kfa');
        print $act eq 'kfa' ? "municao e chaves\n" : "municao completa\n";
    }
    elsif ($act eq 'clip') {
        $mo->{cheats} = ($mo->{cheats} || 0) ^ NOCLIP;
        sync_flags($mo);
        print(($mo->{cheats} & NOCLIP) ? "atravessar paredes ligado\n" : "atravessar paredes desligado\n");
    }
    elsif ($act eq 'chop') {
        $mo->{owns_chainsaw} = 1;
        $mo->{pow_berserk} = 1;
        Doom::Attack::switch_weapon($mo, 'chainsaw');
        print "serra\n";
    }
    elsif ($act eq 'behold') {
        print "v invulneravel, s forca, i invisivel, r traje, a mapa, l luz\n";
    }
    elsif ($act eq 'bv') { _power($mo, 'pow_invul', 'invulneravel'); }
    elsif ($act eq 'bs') { _berserk($mo); }
    elsif ($act eq 'bi') { _power($mo, 'pow_invis', 'invisivel'); sync_flags($mo); }
    elsif ($act eq 'br') { _power($mo, 'pow_suit', 'traje'); }
    elsif ($act eq 'ba') { _power($mo, 'pow_map', 'mapa'); }
    elsif ($act eq 'bl') { _power($mo, 'pow_lite', 'luz'); }
    return;
}

sub tick {
    my ($mo) = @_;
    return if !$mo;
    for my $key (qw(pow_invul pow_invis pow_suit pow_lite)) {
        $mo->{$key}-- if ($mo->{$key} || 0) > 0;
    }
    sync_flags($mo);
    return;
}

sub sync_flags {
    my ($mo) = @_;
    return if !$mo;
    if (($mo->{cheats} || 0) & NOCLIP) {
        $mo->{flags} |= CLIPF;
    }
    else {
        $mo->{flags} &= ~CLIPF;
    }
    if (($mo->{pow_invis} || 0) > 0) {
        $mo->{flags} |= SHADOW;
    }
    else {
        $mo->{flags} &= ~SHADOW;
    }
    return;
}

sub _arsenal {
    my ($mo, $keys) = @_;
    $mo->{owns_shotgun} = 1;
    $mo->{owns_chaingun} = 1;
    $mo->{owns_rocket} = 1;
    $mo->{owns_plasma} = 1;
    $mo->{owns_bfg} = 1;
    $mo->{owns_ssg} = 1;
    $mo->{owns_chainsaw} = 1;
    $mo->{ammo} = $mo->{maxammo} || 200;
    $mo->{shells} = $mo->{maxshells} || 50;
    $mo->{rockets} = $mo->{maxrockets} || 50;
    $mo->{cells} = $mo->{maxcells} || 300;
    $mo->{armorpoints} = 200;
    $mo->{armortype} = 2;
    $mo->{cards} = [(1) x 6] if $keys;
    return;
}

sub _power {
    my ($mo, $key, $name) = @_;
    if (($mo->{$key} || 0) > 0) {
        $mo->{$key} = 0;
        print "$name desligado\n";
    }
    else {
        $mo->{$key} = POWER;
        print "$name ligado\n";
    }
    return;
}

sub _berserk {
    my ($mo) = @_;
    if (($mo->{pow_berserk} || 0) > 0) {
        $mo->{pow_berserk} = 0;
        print "forca desligada\n";
        return;
    }
    $mo->{pow_berserk} = POWER;
    $mo->{health} = 100 if ($mo->{health} || 0) < 100;
    print "forca ligada\n";
    return;
}

1;
