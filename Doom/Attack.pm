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
# Pistola: Ctrl dispara, o alvo perde vida, o barril estoura.
# O monstro ainda nao anda. Igual a doom/player.py no tiro.

package Doom::Attack;

use strict;
use warnings;

use Doom::Collision qw(aim_slope line_attack set_thing_position);
use Doom::Enemy;
use Doom::Compat qw(as_u32 shar);
use Doom::Defs qw(FRACUNIT MF_DROPOFF MF_FLOAT MF_MISSILE MF_SHOOTABLE MF_SOLID ML_TWOSIDED);
use Doom::Info qw(sprite_name MI_SPAWNHEALTH MI_SPAWNSTATE);

use constant MISSILERANGE => 32 * 64 * FRACUNIT;
use constant MF_NOBLOOD => 0x80000;
use constant MF_CORPSE => 0x100000;
use constant MT_SPIDER => 19;
use constant MT_CYBORG => 21;
use constant MT_PUFF => 37;
use constant MT_BLOOD => 38;
use constant S_BLOOD2 => 91;
use constant S_BLOOD3 => 92;
use constant MI_PAINSTATE => 7;
use constant MI_PAINCHANCE => 8;
use constant MI_DEATHSTATE => 12;
use constant MI_XDEATHSTATE => 13;

my @PISTOL = (
    [0, 4, 0, '', 0, 0],
    [1, 6, 1, 'PISF', 7, 1],
    [2, 4, 0, '', 0, 0],
    [1, 5, 0, '', 0, 0],
);

my @RND = (
    0, 8, 109, 220, 222, 241, 149, 107, 75, 248, 254, 140, 16, 66,
    74, 21, 211, 47, 80, 242, 154, 27, 205, 128, 161, 89, 77, 36,
    95, 110, 85, 48, 212, 140, 211, 249, 22, 79, 200, 50, 28, 188,
    52, 140, 202, 120, 68, 145, 62, 70, 184, 190, 91, 197, 152, 224,
    149, 104, 25, 178, 252, 182, 202, 182, 141, 197, 4, 81, 181, 242,
    145, 42, 39, 227, 156, 198, 225, 193, 219, 93, 122, 175, 249, 0,
    175, 143, 70, 239, 46, 246, 163, 53, 163, 109, 168, 135, 2, 235,
    25, 92, 20, 145, 138, 77, 69, 166, 78, 176, 173, 212, 166, 113,
    94, 161, 41, 50, 239, 49, 111, 164, 70, 60, 2, 37, 171, 75,
    136, 156, 11, 56, 42, 146, 138, 229, 73, 146, 77, 61, 98, 196,
    135, 106, 63, 197, 195, 86, 96, 203, 113, 101, 170, 247, 181, 113,
    80, 250, 108, 7, 255, 237, 129, 226, 79, 107, 112, 166, 103, 241,
    24, 223, 239, 120, 198, 58, 60, 82, 128, 3, 184, 66, 143, 224,
    145, 224, 81, 206, 163, 45, 63, 90, 168, 114, 59, 33, 159, 95,
    28, 139, 123, 98, 125, 196, 15, 70, 194, 253, 54, 14, 109, 226,
    71, 17, 161, 93, 186, 87, 244, 138, 20, 52, 123, 251, 26, 36,
    17, 46, 52, 231, 232, 76, 31, 221, 84, 37, 216, 165, 212, 106,
    197, 242, 98, 43, 39, 175, 254, 145, 190, 84, 118, 222, 187, 136,
    120, 163, 236, 249,
);
die "tabela de sorteio\n" if @RND != 256;

my $prnd = 0;

sub p_random {
    $prnd = ($prnd + 1) & 255;
    return $RND[$prnd];
}

sub weapon_think {
    my ($world, $mo, $firing, $sky) = @_;
    return if !$mo;
    $sky = -1 if !defined $sky;
    $mo->{flash_tics} ||= 0;
    if ($mo->{flash_tics} > 0) {
        $mo->{flash_tics}--;
        if ($mo->{flash_tics} <= 0) {
            $mo->{gunflash} = '';
            $mo->{extralight} = 0;
        }
    }
    return if ($mo->{health} || 0) <= 0;
    my $ammo_ok = ($mo->{ammo} || 0) >= 1;
    if (($mo->{gunstate} || '') eq 'atk') {
        $mo->{attackdown} = 1 if $firing;
        $mo->{guntics}-- if ($mo->{guntics} || 0) > 0;
        return if ($mo->{guntics} || 0) > 0;
        $mo->{gunstep}++;
        _enter_atk($world, $mo, $firing, $ammo_ok, $sky);
        return;
    }
    if ($firing && $ammo_ok) {
        $mo->{gunstate} = 'atk';
        $mo->{gunstep} = 0;
        $mo->{attackdown} = 1;
        _enter_atk($world, $mo, $firing, $ammo_ok, $sky);
        return;
    }
    $mo->{gunsprite} = 'PISG';
    $mo->{gunframe} = 0;
    $mo->{gunstate} = 'ready';
    if (!$firing) {
        $mo->{attackdown} = 0;
        $mo->{refire} = 0;
    }
    return;
}

sub _enter_atk {
    my ($world, $mo, $firing, $ammo_ok, $sky) = @_;
    while (1) {
        if (($mo->{gunstep} || 0) >= @PISTOL) {
            if ($firing && $ammo_ok) {
                $mo->{gunstep} = 0;
                next;
            }
            $mo->{gunsprite} = 'PISG';
            $mo->{gunframe} = 0;
            $mo->{guntics} = 0;
            $mo->{gunstate} = 'ready';
            if (!$firing) {
                $mo->{attackdown} = 0;
                $mo->{refire} = 0;
            }
            return;
        }
        my ($frame, $tics, $fire, $flash, $flash_tics, $light) = @{$PISTOL[$mo->{gunstep}]};
        $mo->{gunsprite} = 'PISG';
        $mo->{gunframe} = $frame;
        $mo->{guntics} = $tics;
        $mo->{gunstate} = 'atk';
        if ($flash_tics) {
            $mo->{gunflash} = $flash;
            $mo->{gunflashframe} = 0;
            $mo->{flash_tics} = $flash_tics;
        }
        $mo->{extralight} = $light if $light;
        _do_shot($world, $mo, $sky) if $fire;
        return if $tics > 0;
        $mo->{gunstep}++;
    }
}

sub _bullet_slope {
    my ($world, $mo) = @_;
    my $base = $mo->{angle};
    my $left = as_u32($base + (1 << 26));
    my $right = as_u32($left - (2 << 26));
    for my $ang ($base, $left, $right) {
        my ($slope, $target) = aim_slope($world, $mo, $ang, MISSILERANGE);
        return $slope if $target;
    }
    return 0;
}

sub _do_shot {
    my ($world, $mo, $sky) = @_;
    return if ($mo->{ammo} || 0) < 1;
    $mo->{ammo}--;
    print "sem balas\n" if $mo->{ammo} <= 0;
    my $accurate = !$mo->{refire};
    my $damage = 5 * ((p_random() % 3) + 1);
    my $angle = $mo->{angle};
    $angle = as_u32($angle + (p_random() - p_random()) * 262144) if !$accurate;
    my $slope = _bullet_slope($world, $mo);
    line_attack($world, $mo, $angle, MISSILERANGE, $sky, $slope,
        sub {
            my (undef, $x, $y, $z) = @_;
            _spawn_puff($world, $x, $y, $z);
        },
        sub {
            my ($th, $x, $y, $z) = @_;
            if (($th->{flags} || 0) & MF_NOBLOOD) {
                _spawn_puff($world, $x, $y, $z);
            }
            else {
                _spawn_blood($world, $x, $y, $z, $damage);
            }
            damage_mobj($world, $th, $mo, $damage);
        });
    $mo->{refire}++;
    return;
}

sub tick_mobjs {
    my ($world) = @_;
    my @list = @{$world->{mobjs} || []};
    for my $mo (@list) {
        next if !$mo || $mo->{player} || !$mo->{alive};
        if (($mo->{flags} || 0) & MF_MISSILE) {
            Doom::Enemy::tick_missile($world, $mo);
            next if !$mo->{alive};
        }
        next if !defined $mo->{istate} || ($mo->{tics} || 0) == -1;
        $mo->{tics}--;
        if ($mo->{tics} <= 0) {
            my $st = $Doom::Info::STATES[$mo->{istate}];
            set_mobj_state($world, $mo, $st ? $st->[4] : 0);
        }
    }
    return;
}

sub damage_mobj {
    my ($world, $target, $source, $damage) = @_;
    return if !$target || !$target->{alive} || !(($target->{flags} || 0) & MF_SHOOTABLE);
    return if $damage <= 0;
    if ($target->{player}) {
        my $hurt = $damage;
        if ($target->{armortype}) {
            my $saved = int($hurt / ($target->{armortype} == 1 ? 3 : 2));
            my $pts = $target->{armorpoints} || 0;
            if ($pts <= $saved) {
                $saved = $pts;
                $target->{armortype} = 0;
            }
            $target->{armorpoints} = $pts - $saved;
            $hurt -= $saved;
        }
        $target->{health} -= $hurt;
        $target->{health} = 0 if $target->{health} < 0;
        print "vida $target->{health}\n";
        return;
    }
    $target->{target} = $source if $source && $source != $target;
    $target->{health} -= $damage;
    if ($target->{health} <= 0) {
        _kill($world, $target);
        return;
    }
    my $info = $Doom::Info::MOBJINFO[$target->{type}];
    return if !$info;
    if (p_random() < ($info->[MI_PAINCHANCE] || 0) && $info->[MI_PAINSTATE]) {
        set_mobj_state($world, $target, $info->[MI_PAINSTATE]);
    }
    return;
}

sub _kill {
    my ($world, $mo) = @_;
    $mo->{flags} &= ~(MF_SHOOTABLE | MF_FLOAT);
    $mo->{flags} |= MF_CORPSE | MF_DROPOFF;
    $mo->{height} = int(($mo->{height} || 0) / 4);
    my $info = $Doom::Info::MOBJINFO[$mo->{type} || 0];
    return if !$info;
    my $xds = $info->[MI_XDEATHSTATE] || 0;
    my $st = ($mo->{health} < -($info->[MI_SPAWNHEALTH] || 0) && $xds)
        ? $xds
        : ($info->[MI_DEATHSTATE] || 0);
    set_mobj_state($world, $mo, $st);
    if ($mo->{alive}) {
        $mo->{tics} -= p_random() & 3;
        $mo->{tics} = 1 if ($mo->{tics} || 0) < 1;
    }
    return;
}

sub set_mobj_state {
    my ($world, $mo, $state) = @_;
    my $safety = 0;
    while (1) {
        return 0 if !$mo || !$mo->{alive};
        if (!$state) {
            _remove($world, $mo);
            return 0;
        }
        my $st = $Doom::Info::STATES[$state];
        if (!$st) {
            _remove($world, $mo);
            return 0;
        }
        my $act = $Doom::Info::ACTIONS[$st->[3] || 0] || '';
        $mo->{istate} = $state;
        $mo->{tics} = $st->[2];
        $mo->{sprite} = sprite_name($st->[0]);
        $mo->{frame} = $st->[1];
        if ($act eq 'Fall') {
            $mo->{flags} &= ~MF_SOLID;
        }
        elsif ($act eq 'Explode') {
            _radius_attack($world, $mo, 128);
            return 0 if !$mo->{alive};
        }
        elsif ($act) {
            Doom::Enemy::call_action($world, $mo, $act);
            return 0 if !$mo->{alive};
        }
        $state = $st->[4];
        return 1 if ($mo->{tics} || 0) != 0;
        $safety++;
        return 1 if $safety > 100;
    }
}

sub _remove {
    my ($world, $mo) = @_;
    return if !$mo || $mo->{player};
    Doom::Collision::unset_thing_position($world, $mo);
    $mo->{alive} = 0;
    $mo->{istate} = 0;
    $mo->{flags} = 0;
    my $list = $world->{mobjs} || [];
    for (my $i = $#$list; $i >= 0; $i--) {
        if ($list->[$i] && $list->[$i] == $mo) {
            splice @$list, $i, 1;
            last;
        }
    }
    return;
}

sub _spawn_fx {
    my ($world, $x, $y, $z, $type) = @_;
    my $info = $Doom::Info::MOBJINFO[$type];
    return if !$info;
    my $stn = $info->[MI_SPAWNSTATE];
    my $st = $Doom::Info::STATES[$stn];
    return if !$st;
    $z += (p_random() - p_random()) * 1024;
    my $mo = {
        x => $x, y => $y, z => $z, angle => 0,
        radius => $info->[16], height => $info->[17],
        floorz => $z, ceilingz => $z,
        flags => $info->[21], health => $info->[MI_SPAWNHEALTH],
        type => $type, doomednum => -1, player => undef, alive => 1,
        istate => $stn, tics => $st->[2],
        sprite => sprite_name($st->[0]), frame => $st->[1],
    };
    $mo->{tics} -= p_random() & 3;
    $mo->{tics} = 1 if $mo->{tics} < 1;
    push @{$world->{mobjs}}, $mo;
    set_thing_position($world, $mo);
    return $mo;
}

sub _spawn_puff {
    my ($world, $x, $y, $z) = @_;
    return _spawn_fx($world, $x, $y, $z, MT_PUFF);
}

sub _spawn_blood {
    my ($world, $x, $y, $z, $damage) = @_;
    my $mo = _spawn_fx($world, $x, $y, $z, MT_BLOOD);
    return if !$mo;
    if ($damage < 9) {
        set_mobj_state($world, $mo, S_BLOOD3);
    }
    elsif ($damage <= 12) {
        set_mobj_state($world, $mo, S_BLOOD2);
    }
    return $mo;
}

sub _sees {
    my ($world, $from, $to) = @_;
    my $blocked = 0;
    Doom::Collision::path_traverse($world, $from->{x}, $from->{y}, $to->{x}, $to->{y}, 1, sub {
        my $li = $_[0]{line};
        if (!$li || !($li->{flags} & ML_TWOSIDED)) {
            $blocked = 1;
            return 0;
        }
        my ($top, $bot) = Doom::Collision::line_opening($li);
        if ($bot >= $top) {
            $blocked = 1;
            return 0;
        }
        return 1;
    });
    return !$blocked;
}

sub _radius_attack {
    my ($world, $spot, $damage) = @_;
    my $source = $spot->{target} || $spot;
    my @list = @{$world->{mobjs} || []};
    for my $other (@list) {
        next if !$other || $other == $spot || !(($other->{flags} || 0) & MF_SHOOTABLE);
        next if ($other->{type} || 0) == MT_SPIDER || ($other->{type} || 0) == MT_CYBORG;
        my $dx = abs($other->{x} - $spot->{x});
        my $dy = abs($other->{y} - $spot->{y});
        my $dist = ($dx > $dy ? $dx : $dy) - ($other->{radius} || 0);
        $dist = 0 if $dist < 0;
        $dist = shar($dist, 16);
        next if $dist >= $damage;
        next if !_sees($world, $other, $spot);
        damage_mobj($world, $other, $source, $damage - $dist);
    }
    return;
}

1;
