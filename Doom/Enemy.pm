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
# O monstro ve, anda e revida. Igual a doom/enemy.py.
# Ainda nao ha som.

package Doom::Enemy;

use strict;
use warnings;

use Doom::Collision qw(aim_slope approx_distance line_attack try_move);
use Doom::Compat qw(as_u32 fixed_mul shar);
use Doom::Defs qw(
    ANG90 FRACUNIT
    MF_MISSILE MF_SHOOTABLE
    ML_TWOSIDED
);
use Doom::Info qw(sprite_name MI_SPAWNSTATE);
use Doom::Tables qw(fine_cos fine_sin);

use constant MELEERANGE => 64 * FRACUNIT;
use constant MISSILERANGE => 32 * 64 * FRACUNIT;
use constant ANG270 => 0xC0000000;
use constant DI_NODIR => 8;
use constant MF_AMBUSH => 32;
use constant MF_JUSTHIT => 64;
use constant MF_JUSTATTACKED => 128;
use constant MT_TROOPSHOT => 31;
use constant MI_SEESTATE => 3;
use constant MI_MELEESTATE => 10;
use constant MI_MISSILESTATE => 11;
use constant MI_DEATHSTATE => 12;
use constant MI_SPEED => 15;
use constant MI_DAMAGE => 19;

my @XSPEED = (65536, 47000, 0, -47000, -65536, -47000, 0, 47000);
my @YSPEED = (0, 47000, 65536, 47000, 0, -47000, -65536, -47000);
my @OPPOSITE = (4, 5, 6, 7, 0, 1, 2, 3, 8);
my @DIAGS = (3, 1, 5, 7);

sub call_action {
    my ($world, $mo, $act) = @_;
    return if !$mo || !$act;
    if ($act eq 'Look') {
        _look($world, $mo);
    }
    elsif ($act eq 'Chase') {
        _chase($world, $mo);
    }
    elsif ($act eq 'FaceTarget') {
        _face($mo, $mo->{target}) if $mo->{target};
    }
    elsif ($act eq 'PosAttack') {
        _hitscan($world, $mo, 1, 5, 3);
    }
    elsif ($act eq 'SPosAttack') {
        _hitscan($world, $mo, 3, 5, 3);
    }
    elsif ($act eq 'TroopAttack') {
        _melee_or_ball($world, $mo, MT_TROOPSHOT, 3);
    }
    elsif ($act eq 'SargAttack') {
        _melee($world, $mo, 4);
    }
    return;
}

sub tick_missile {
    my ($world, $mo) = @_;
    return if !$mo || !(($mo->{flags} || 0) & MF_MISSILE) || !$mo->{alive};
    $mo->{z} += $mo->{momz} || 0;
    $mo->{_hitthing} = undef;
    my $ok = try_move($world, $mo, $mo->{x} + ($mo->{momx} || 0), $mo->{y} + ($mo->{momy} || 0));
    my $hit = $mo->{_hitthing};
    if (!$ok || $mo->{z} <= ($mo->{floorz} || 0) || $mo->{z} + $mo->{height} >= ($mo->{ceilingz} || 0)) {
        _boom($world, $mo, $hit);
    }
    return;
}

sub _player {
    my ($world) = @_;
    for my $mo (@{$world->{mobjs} || []}) {
        return $mo if $mo && $mo->{player};
    }
    return;
}

sub _info {
    my ($mo) = @_;
    return if !$mo || !defined $mo->{type};
    return $Doom::Info::MOBJINFO[$mo->{type}];
}

sub _look {
    my ($world, $mo) = @_;
    $mo->{threshold} = 0;
    my $pl = _player($world);
    return if !$pl || !(($pl->{flags} || 0) & MF_SHOOTABLE);
    return if !_see_player($world, $mo, $pl, 0);
    $mo->{movedir} = DI_NODIR;
    $mo->{movecount} = 0;
    my $info = _info($mo);
    my $see = $info ? ($info->[MI_SEESTATE] || 0) : 0;
    Doom::Attack::set_mobj_state($world, $mo, $see) if $see;
    return;
}

sub _see_player {
    my ($world, $mo, $pl, $all) = @_;
    return 0 if !$pl || ($pl->{health} || 0) <= 0 || !(($pl->{flags} || 0) & MF_SHOOTABLE);
    return 0 if !_sight($world, $mo, $pl);
    if (!$all) {
        my $ang = as_u32(Doom::Collision::angle_to($mo->{x}, $mo->{y}, $pl->{x}, $pl->{y}) - $mo->{angle});
        if ($ang > ANG90 && $ang < ANG270) {
            my $dist = approx_distance($pl->{x} - $mo->{x}, $pl->{y} - $mo->{y});
            return 0 if $dist > MELEERANGE;
        }
    }
    $mo->{target} = $pl;
    return 1;
}

sub _sight {
    my ($world, $a, $b) = @_;
    return 0 if !$a || !$b;
    my $eye = $a->{z} + $a->{height} - int($a->{height} / 4);
    my $top = ($b->{z} + $b->{height}) - $eye;
    my $bot = $b->{z} - $eye;
    my $blocked = 0;
    Doom::Collision::path_traverse($world, $a->{x}, $a->{y}, $b->{x}, $b->{y}, 1, sub {
        my $inn = $_[0];
        my $li = $inn->{line};
        if (!$li || !$li->{backsector} || !($li->{flags} & ML_TWOSIDED)) {
            $blocked = 1;
            return 0;
        }
        my ($opentop, $openbottom) = Doom::Collision::line_opening($li);
        my $frac = $inn->{frac} || 0;
        my $z_hi = $eye + fixed_mul($top, $frac);
        my $z_lo = $eye + fixed_mul($bot, $frac);
        if ($z_lo >= $opentop || $z_hi <= $openbottom) {
            $blocked = 1;
            return 0;
        }
        return 1;
    });
    return !$blocked;
}

sub _chase {
    my ($world, $mo) = @_;
    $mo->{reactiontime}-- if $mo->{reactiontime};
    if ($mo->{threshold}) {
        my $tgt = $mo->{target};
        if (!$tgt || ($tgt->{health} || 0) <= 0) {
            $mo->{threshold} = 0;
        }
        else {
            $mo->{threshold}--;
        }
    }
    _face_dir($mo) if ($mo->{movedir} || 0) < 8;
    my $pl = _player($world);
    my $target = $mo->{target};
    if (!$target || ($target->{health} || 0) <= 0 || !(($target->{flags} || 0) & MF_SHOOTABLE)) {
        if (!_see_player($world, $mo, $pl, 1)) {
            my $info = _info($mo);
            my $spawn = $info ? ($info->[MI_SPAWNSTATE] || 0) : 0;
            Doom::Attack::set_mobj_state($world, $mo, $spawn) if $spawn;
        }
        return;
    }
    if (($mo->{flags} || 0) & MF_JUSTATTACKED) {
        $mo->{flags} &= ~MF_JUSTATTACKED;
        _new_dir($world, $mo);
        return;
    }
    my $dist = approx_distance($target->{x} - $mo->{x}, $target->{y} - $mo->{y});
    my $info = _info($mo) || [];
    my $melee = $info->[MI_MELEESTATE] || 0;
    my $miss = $info->[MI_MISSILESTATE] || 0;
    if ($melee && $dist < MELEERANGE - 20 * FRACUNIT + ($target->{radius} || 0)
        && _sight($world, $mo, $target)) {
        Doom::Attack::set_mobj_state($world, $mo, $melee);
        return;
    }
    if ($miss && !$mo->{reactiontime} && (($mo->{movecount} || 0) == 0 || (($mo->{flags} || 0) & MF_JUSTHIT))
        && _missile_ok($world, $mo, $target, $dist, $melee)) {
        $mo->{flags} &= ~MF_JUSTHIT;
        $mo->{flags} |= MF_JUSTATTACKED;
        Doom::Attack::set_mobj_state($world, $mo, $miss);
        return;
    }
    $mo->{flags} &= ~MF_JUSTHIT;
    $mo->{movecount}--;
    if ($mo->{movecount} < 0 || !_step($world, $mo, $info->[MI_SPEED] || 0)) {
        _new_dir($world, $mo);
    }
    return;
}

sub _missile_ok {
    my ($world, $mo, $target, $dist, $melee) = @_;
    return 0 if $mo->{reactiontime} || !_sight($world, $mo, $target);
    if (($mo->{flags} || 0) & MF_JUSTHIT) {
        return 1;
    }
    my $d = $dist - 64 * FRACUNIT;
    $d -= 128 * FRACUNIT if !$melee;
    $d = 0 if $d < 0;
    $d = shar($d, 16);
    $d = 200 if $d > 200;
    return Doom::Attack::p_random() >= $d;
}

sub _face {
    my ($mo, $t) = @_;
    return if !$mo || !$t;
    $mo->{angle} = Doom::Collision::angle_to($mo->{x}, $mo->{y}, $t->{x}, $t->{y});
    return;
}

sub _face_dir {
    my ($mo) = @_;
    my $dir = $mo->{movedir} || 0;
    return if $dir < 0 || $dir >= 8;
    $mo->{angle} = as_u32(($mo->{angle} || 0) & 0xE0000000);
    my $want = as_u32($dir * 0x20000000);
    my $delta = $mo->{angle} - $want;
    $delta -= 4294967296 if $delta > 2147483647;
    $delta += 4294967296 if $delta < -2147483648;
    if ($delta > 0) {
        $mo->{angle} = as_u32($mo->{angle} - 0x20000000);
    }
    elsif ($delta < 0) {
        $mo->{angle} = as_u32($mo->{angle} + 0x20000000);
    }
    return;
}

sub _step {
    my ($world, $mo, $speed) = @_;
    my $dir = $mo->{movedir};
    return 0 if !defined $dir || $dir < 0 || $dir >= 8;
    my $nx = $mo->{x} + $speed * $XSPEED[$dir];
    my $ny = $mo->{y} + $speed * $YSPEED[$dir];
    if (!try_move($world, $mo, $nx, $ny)) {
        my $spec = $world->{specials};
        my $hits = $Doom::Collision::LAST_SPECHIT || [];
        for (my $i = $#$hits; $i >= 0; $i--) {
            my $ln = $hits->[$i];
            my $kind = $ln->{special} || 0;
            next if !$kind;
            next if $kind == 26 || $kind == 27 || $kind == 28;
            next if $kind == 32 || $kind == 33 || $kind == 34;
            if ($spec && $spec->use_special($ln, $mo, 0)) {
                return 1;
            }
        }
        return 0;
    }
    $mo->{z} = $mo->{floorz};
    return 1;
}

sub _new_dir {
    my ($world, $mo) = @_;
    my $t = $mo->{target};
    return if !$t;
    my $old = defined $mo->{movedir} ? $mo->{movedir} : DI_NODIR;
    $old = DI_NODIR if $old < 0 || $old > 8;
    my $turn = $OPPOSITE[$old];
    my $info = _info($mo) || [];
    my $speed = $info->[MI_SPEED] || 0;
    my $dx = $t->{x} - $mo->{x};
    my $dy = $t->{y} - $mo->{y};
    my $d2 = $dx > 10 * FRACUNIT ? 0 : ($dx < -10 * FRACUNIT ? 4 : DI_NODIR);
    my $d3 = $dy < -10 * FRACUNIT ? 6 : ($dy > 10 * FRACUNIT ? 2 : DI_NODIR);
    if ($d2 != DI_NODIR && $d3 != DI_NODIR) {
        $mo->{movedir} = $DIAGS[($dy < 0 ? 2 : 0) + ($dx > 0 ? 1 : 0)];
        if ($mo->{movedir} != $turn && _step($world, $mo, $speed)) {
            $mo->{movecount} = Doom::Attack::p_random() & 15;
            return;
        }
    }
    if (Doom::Attack::p_random() > 200 || abs($dy) > abs($dx)) {
        ($d2, $d3) = ($d3, $d2);
    }
    $d2 = DI_NODIR if $d2 == $turn;
    $d3 = DI_NODIR if $d3 == $turn;
    for my $d ($d2, $d3, $old) {
        next if $d == DI_NODIR;
        $mo->{movedir} = $d;
        if (_step($world, $mo, $speed)) {
            $mo->{movecount} = Doom::Attack::p_random() & 15;
            return;
        }
    }
    my @dirs = (Doom::Attack::p_random() & 1) ? (0 .. 7) : reverse(0 .. 7);
    for my $d (@dirs) {
        next if $d == $turn;
        $mo->{movedir} = $d;
        if (_step($world, $mo, $speed)) {
            $mo->{movecount} = Doom::Attack::p_random() & 15;
            return;
        }
    }
    if ($turn != DI_NODIR) {
        $mo->{movedir} = $turn;
        if (_step($world, $mo, $speed)) {
            $mo->{movecount} = Doom::Attack::p_random() & 15;
            return;
        }
    }
    $mo->{movedir} = DI_NODIR;
    $mo->{movecount} = Doom::Attack::p_random() & 15;
    return;
}

sub _hitscan {
    my ($world, $mo, $pellets, $faces, $mul) = @_;
    my $t = $mo->{target};
    return if !$t;
    _face($mo, $t);
    my ($slope) = aim_slope($world, $mo, $mo->{angle}, MISSILERANGE);
    my $saved = $mo->{angle};
    my $sky = defined $world->{skyflat} ? $world->{skyflat} : -1;
    for (1 .. $pellets) {
        my $spread = (Doom::Attack::p_random() - Doom::Attack::p_random()) * 1048576;
        $mo->{angle} = as_u32($saved + $spread);
        my $damage = ((Doom::Attack::p_random() % $faces) + 1) * $mul;
        line_attack($world, $mo, $mo->{angle}, MISSILERANGE, $sky, $slope,
            sub {
                my (undef, $x, $y, $z) = @_;
                Doom::Attack::_spawn_puff($world, $x, $y, $z);
            },
            sub {
                my ($th, $x, $y, $z) = @_;
                if (($th->{flags} || 0) & 0x80000) {
                    Doom::Attack::_spawn_puff($world, $x, $y, $z);
                }
                else {
                    Doom::Attack::_spawn_blood($world, $x, $y, $z, $damage);
                }
                Doom::Attack::damage_mobj($world, $th, $mo, $damage);
            });
    }
    $mo->{angle} = $saved;
    return;
}

sub _melee {
    my ($world, $mo, $mul) = @_;
    my $t = $mo->{target};
    return 0 if !$t;
    _face($mo, $t);
    my $dist = approx_distance($t->{x} - $mo->{x}, $t->{y} - $mo->{y});
    return 0 if $dist >= MELEERANGE + ($mo->{radius} || 0);
    Doom::Attack::damage_mobj($world, $t, $mo, ((Doom::Attack::p_random() % 8) + 1) * $mul);
    return 1;
}

sub _melee_or_ball {
    my ($world, $mo, $type, $mul) = @_;
    return if !$mo->{target};
    return if _melee($world, $mo, $mul);
    _spawn_ball($world, $mo, $mo->{target}, $type);
    return;
}

sub _spawn_ball {
    my ($world, $src, $dest, $type) = @_;
    my $info = $Doom::Info::MOBJINFO[$type];
    return if !$info;
    my $stn = $info->[MI_SPAWNSTATE];
    my $st = $Doom::Info::STATES[$stn];
    return if !$st;
    my $ang = Doom::Collision::angle_to($src->{x}, $src->{y}, $dest->{x}, $dest->{y});
    my $ahead = shar(($src->{radius} || 0) + ($info->[16] || 0), 16) + 1;
    my $x = $src->{x} + $ahead * fine_cos($ang);
    my $y = $src->{y} + $ahead * fine_sin($ang);
    my $z = $src->{z} + 32 * FRACUNIT;
    my $sub = $world->point_in_subsector($x, $y);
    my $speed = $info->[MI_SPEED] || 0;
    my $dist = approx_distance($dest->{x} - $x, $dest->{y} - $y);
    my $steps = $speed ? int($dist / $speed) : 1;
    $steps = 1 if $steps < 1;
    my $mo = {
        x => $x, y => $y, z => $z, angle => $ang,
        radius => $info->[16], height => $info->[17],
        floorz => $sub->{sector}{floorheight},
        ceilingz => $sub->{sector}{ceilingheight},
        flags => $info->[21], health => 100, type => $type,
        doomednum => -1, player => undef, alive => 1, target => $src,
        istate => $stn, tics => $st->[2],
        sprite => sprite_name($st->[0]), frame => $st->[1],
        momx => fixed_mul($speed, fine_cos($ang)),
        momy => fixed_mul($speed, fine_sin($ang)),
        momz => int(($dest->{z} + int(($dest->{height} || 0) / 2) - $z) / $steps),
        movedir => DI_NODIR, movecount => 0, reactiontime => 0,
    };
    push @{$world->{mobjs}}, $mo;
    return $mo;
}

sub _boom {
    my ($world, $mo, $hit) = @_;
    return if !$mo || !(($mo->{flags} || 0) & MF_MISSILE);
    $mo->{flags} &= ~MF_MISSILE;
    $mo->{momx} = 0;
    $mo->{momy} = 0;
    $mo->{momz} = 0;
    if ($hit && (($hit->{flags} || 0) & MF_SHOOTABLE) && $hit != $mo->{target}) {
        my $info = _info($mo) || [];
        my $dmg = ($info->[MI_DAMAGE] || 0) * ((Doom::Attack::p_random() % 8) + 1);
        Doom::Attack::damage_mobj($world, $hit, $mo->{target} || $mo, $dmg) if $dmg > 0;
    }
    my $info = _info($mo);
    my $death = $info ? ($info->[MI_DEATHSTATE] || 0) : 0;
    Doom::Attack::set_mobj_state($world, $mo, $death);
    return;
}

1;
