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
# O tiro acorda quem esta atras da porta aberta.

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
use constant ML_SOUNDBLOCK => 64;
use constant MT_TROOPSHOT => 31;
use constant MI_SEESTATE => 3;
use constant MI_MELEESTATE => 10;
use constant MI_MISSILESTATE => 11;
use constant MI_DEATHSTATE => 12;
use constant MI_SPEED => 15;
use constant MI_DAMAGE => 19;
use constant MF_SKULLFLY => 0x1000000;
use constant MF_CORPSE => 0x100000;
use constant MF_COUNTKILL => 0x400000;
use constant SKULLSPEED => 20 * FRACUNIT;
use constant TRACEANGLE => 0x0c000000;
use constant FATSPREAD => 0x08000000;
use constant MAXSKULLS => 20;

my @brain;
my $brain_on = 0;
my $fast_on;
my @sarg_tics;
my %shot_speed;

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
    elsif ($act eq 'BFGSpray') {
        _bfg_spray($world, $mo);
    }
    elsif ($act eq 'CPosAttack') {
        Doom::Sound::at($world, 'shotgn');
        _hitscan($world, $mo, 1, 5, 3);
    }
    elsif ($act eq 'CPosRefire' || $act eq 'SpidRefire') {
        _refire($world, $mo, $act eq 'CPosRefire' ? 40 : 10);
    }
    elsif ($act eq 'HeadAttack') {
        _melee_or_ball($world, $mo, 32, 10);
    }
    elsif ($act eq 'BruisAttack') {
        _melee_or_ball($world, $mo, 16, 10);
    }
    elsif ($act eq 'SkullAttack') {
        _skull_attack($world, $mo);
    }
    elsif ($act eq 'CyberAttack') {
        _ball($world, $mo, 33);
    }
    elsif ($act eq 'BspiAttack') {
        _ball($world, $mo, 36);
    }
    elsif ($act eq 'PainAttack') {
        _pain_shoot($world, $mo, $mo->{angle} || 0);
    }
    elsif ($act eq 'PainDie') {
        $mo->{flags} &= ~0x2;
        _pain_shoot($world, $mo, as_u32(($mo->{angle} || 0) + $_)) for (ANG90, ANG90 * 2, ANG270);
    }
    elsif ($act eq 'FatRaise') {
        _face($mo, $mo->{target}) if $mo->{target};
        Doom::Sound::at($world, 'manatk');
    }
    elsif ($act =~ /\AFatAttack([123])\z/) {
        _fat($world, $mo, $1);
    }
    elsif ($act eq 'SkelWhoosh') {
        _face($mo, $mo->{target}) if $mo->{target};
        Doom::Sound::at($world, 'skeswg');
    }
    elsif ($act eq 'SkelFist') {
        Doom::Sound::at($world, 'skepch') if _melee($world, $mo, 6);
    }
    elsif ($act eq 'SkelMissile') {
        my $miss = _ball($world, $mo, 6);
        if ($miss) {
            $miss->{tracer} = $mo->{target};
            $miss->{z} += 16 * FRACUNIT;
        }
    }
    elsif ($act eq 'Tracer') {
        _tracer_home($mo) if !(($world->{leveltime} || 0) & 3);
    }
    elsif ($act eq 'VileStart' || $act eq 'VileAttack') {
        _vile_attack($world, $mo);
    }
    elsif ($act eq 'VileTarget') {
        _vile_target($world, $mo);
    }
    elsif ($act eq 'VileChase') {
        _chase($world, $mo) if !_vile_chase($world, $mo);
    }
    elsif ($act eq 'StartFire' || $act eq 'Fire' || $act eq 'FireCrackle') {
        Doom::Sound::at($world, $act eq 'FireCrackle' ? 'flame' : 'flamst') if $act ne 'Fire';
        _fire_follow($mo);
    }
    elsif ($act eq 'Metal' || $act eq 'BabyMetal' || $act eq 'Hoof') {
        Doom::Sound::at($world, $act eq 'Hoof' ? 'hoof' : $act eq 'BabyMetal' ? 'bspwlk' : 'metal');
        _chase($world, $mo);
    }
    elsif ($act eq 'BossDeath') {
        _boss_death($world, $mo);
    }
    elsif ($act eq 'KeenDie') {
        $mo->{flags} &= ~0x2;
        _boss_death($world, $mo, 1);
    }
    elsif ($act eq 'BrainAwake') {
        @brain = grep { ($_->{type} || 0) == 27 } @{$world->{mobjs} || []};
        $brain_on = 0;
        Doom::Sound::at($world, 'bossit');
    }
    elsif ($act eq 'BrainSpit') {
        _brain_spit($world, $mo);
    }
    elsif ($act eq 'BrainDie') {
        $world->{specials}{exit} = 1 if $world->{specials};
    }
    elsif ($act eq 'BrainPain') {
        Doom::Sound::at($world, 'bospn');
    }
    elsif ($act eq 'BrainScream') {
        Doom::Sound::at($world, 'bosdth');
    }
    elsif ($act eq 'SpawnSound' || $act eq 'SpawnFly') {
        Doom::Sound::at($world, 'boscub') if $act eq 'SpawnSound';
        _spawn_fly($world, $mo);
    }
    return;
}

sub _bfg_spray {
    my ($world, $ball) = @_;
    my $shooter = $ball && $ball->{target};
    return if !$shooter;
    my $base = $ball->{angle} || 0;
    for my $i (0 .. 39) {
        my $an = as_u32($base - int(ANG90 / 2) + int(ANG90 / 40) * $i);
        my (undef, $target) = aim_slope($world, $shooter, $an, 16 * 64 * FRACUNIT);
        next if !$target;
        my $damage = 0;
        $damage += (Doom::Attack::p_random() & 7) + 1 for 1 .. 15;
        Doom::Attack::damage_mobj($world, $target, $shooter, $damage) if $damage > 0;
        Doom::Attack::_spawn_fx(
            $world, $target->{x}, $target->{y},
            ($target->{z} || 0) + int(($target->{height} || 0) / 4), 42,
        );
    }
    return;
}

sub tick_missile {
    my ($world, $mo) = @_;
    return if !$mo || !(($mo->{flags} || 0) & MF_MISSILE) || !$mo->{alive};
    _tracer_home($mo) if ($mo->{type} || 0) == 6 && !(($world->{leveltime} || 0) & 3);
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

sub noise_alert {
    my ($world, $emitter) = @_;
    return if !$world || !$emitter;
    my $here = $world->point_in_subsector($emitter->{x}, $emitter->{y});
    return if !$here || !$here->{sector};
    $world->{validcount} = ($world->{validcount} || 0) + 1;
    _recursive_sound($world, $here->{sector}, 0, $emitter);
    return;
}

sub _recursive_sound {
    my ($world, $sec, $blocks, $target) = @_;
    return if !$sec;
    my $mark = $blocks + 1;
    if (($sec->{validcount} || 0) == ($world->{validcount} || 0)
        && ($sec->{soundtraversed} || 0) <= $mark)
    {
        return;
    }
    $sec->{validcount} = $world->{validcount};
    $sec->{soundtraversed} = $mark;
    $sec->{soundtarget} = $target;
    for my $ln (@{$sec->{lines} || []}) {
        next if !(($ln->{flags} || 0) & ML_TWOSIDED);
        my ($top, $bot) = Doom::Collision::line_opening($ln);
        next if $top - $bot <= 0;
        my $other = ($ln->{frontsector} && $ln->{frontsector} == $sec)
            ? $ln->{backsector} : $ln->{frontsector};
        next if !$other;
        if (($ln->{flags} || 0) & ML_SOUNDBLOCK) {
            _recursive_sound($world, $other, 1, $target) if $blocks == 0;
        }
        else {
            _recursive_sound($world, $other, $blocks, $target);
        }
    }
    return;
}

sub _look {
    my ($world, $mo) = @_;
    $mo->{threshold} = 0;
    my $see = 0;
    my $here = $world->point_in_subsector($mo->{x}, $mo->{y});
    my $targ = $here && $here->{sector} ? $here->{sector}{soundtarget} : undef;
    if ($targ && ($targ->{health} || 0) > 0 && (($targ->{flags} || 0) & MF_SHOOTABLE)) {
        $mo->{target} = $targ;
        if (($mo->{flags} || 0) & MF_AMBUSH) {
            $see = _sight($world, $mo, $targ) ? 1 : 0;
        }
        else {
            $see = 1;
        }
    }
    if (!$see) {
        my $pl = _player($world);
        return if !_see_player($world, $mo, $pl, 0);
    }
    $mo->{movedir} = DI_NODIR;
    $mo->{movecount} = 0;
    my $info = _info($mo);
    my $hear = $info ? ($info->[4] || '') : '';
    if ($hear eq 'posit1' || $hear eq 'posit2' || $hear eq 'posit3') {
        $hear = (qw(posit1 posit2 posit3))[Doom::Attack::p_random() % 3];
    }
    elsif ($hear eq 'bgsit1' || $hear eq 'bgsit2') {
        $hear = (qw(bgsit1 bgsit2))[Doom::Attack::p_random() % 2];
    }
    Doom::Sound::at($world, $hear) if $hear;
    my $seestate = $info ? ($info->[MI_SEESTATE] || 0) : 0;
    Doom::Attack::set_mobj_state($world, $mo, $seestate) if $seestate;
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
        _new_dir($world, $mo) if ($world->{skill} || 0) < 4;
        return;
    }
    my $dist = approx_distance($target->{x} - $mo->{x}, $target->{y} - $mo->{y});
    my $info = _info($mo) || [];
    my $melee = $info->[MI_MELEESTATE] || 0;
    my $miss = $info->[MI_MISSILESTATE] || 0;
    my $fast = ($world->{skill} || 0) >= 4;
    if ($melee && $dist < MELEERANGE - 20 * FRACUNIT + ($target->{radius} || 0)
        && _sight($world, $mo, $target)) {
        Doom::Attack::set_mobj_state($world, $mo, $melee);
        return;
    }
    if ($miss && !$mo->{reactiontime}
        && ($fast || ($mo->{movecount} || 0) == 0 || (($mo->{flags} || 0) & MF_JUSTHIT))
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
    noise_alert($world, $mo);
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
    my $info = _info($mo);
    my $snd = ($info && $info->[6]) ? $info->[6] : 'claw';
    Doom::Sound::at($world, $snd);
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
    Doom::Sound::at($world, $info->[4]) if $info->[4];
    return $mo;
}

sub spawn_player_missile {
    my ($world, $src, $type) = @_;
    my $info = $Doom::Info::MOBJINFO[$type];
    return if !$info || !$src;
    my $stn = $info->[MI_SPAWNSTATE];
    my $st = $Doom::Info::STATES[$stn];
    return if !$st;
    my $base = $src->{angle} || 0;
    my $left = as_u32($base + (1 << 26));
    my $right = as_u32($left - (2 << 26));
    my ($ang, $slope) = ($base, 0);
    for my $try ($base, $left, $right) {
        my ($s, $target) = aim_slope($world, $src, $try, MISSILERANGE);
        if ($target) {
            ($ang, $slope) = ($try, $s);
            last;
        }
    }
    my $speed = $info->[MI_SPEED] || 0;
    my $z = ($src->{z} || 0) + 32 * FRACUNIT;
    my $mo = {
        x => $src->{x}, y => $src->{y}, z => $z, angle => $ang,
        radius => $info->[16], height => $info->[17],
        flags => $info->[21] || 0, health => $info->[2] || 100, type => $type,
        doomednum => -1, player => undef, alive => 1, target => $src,
        istate => $stn, tics => $st->[2],
        sprite => sprite_name($st->[0]), frame => $st->[1],
        momx => fixed_mul($speed, fine_cos($ang)),
        momy => fixed_mul($speed, fine_sin($ang)),
        momz => fixed_mul($speed, $slope),
        movedir => DI_NODIR, movecount => 0, reactiontime => 0,
    };
    my $sub = $world->point_in_subsector($mo->{x}, $mo->{y});
    if ($sub && $sub->{sector}) {
        $mo->{floorz} = $sub->{sector}{floorheight};
        $mo->{ceilingz} = $sub->{sector}{ceilingheight};
    }
    push @{$world->{mobjs}}, $mo;
    my $nx = $mo->{x} + int(($mo->{momx} || 0) / 2);
    my $ny = $mo->{y} + int(($mo->{momy} || 0) / 2);
    $mo->{z} += int(($mo->{momz} || 0) / 2);
    _boom($world, $mo, $mo->{_hitthing}) if !try_move($world, $mo, $nx, $ny);
    return $mo;
}

sub _boom {
    my ($world, $mo, $hit) = @_;
    return if !$mo || !(($mo->{flags} || 0) & MF_MISSILE);
    $mo->{flags} &= ~MF_MISSILE;
    $mo->{momx} = 0;
    $mo->{momy} = 0;
    $mo->{momz} = 0;
    my $fx = _info($mo);
    Doom::Sound::at($world, $fx->[14]) if $fx && $fx->[14];
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

sub apply_fast {
    my ($world) = @_;
    my $want = ($world->{skill} || 0) >= 4 ? 1 : 0;
    $world->{respawn} = $want;
    if (!@sarg_tics) {
        @sarg_tics = map { $Doom::Info::STATES[$_][2] } 477 .. 489;
        $shot_speed{$_} = $Doom::Info::MOBJINFO[$_][15] for (16, 31, 32);
    }
    return if defined $fast_on && $fast_on == $want;
    $fast_on = $want;
    for my $i (0 .. $#sarg_tics) {
        my $t = $want ? int($sarg_tics[$i] / 2) : $sarg_tics[$i];
        $t = 1 if $t < 1;
        $Doom::Info::STATES[477 + $i][2] = $t;
    }
    for my $mt (keys %shot_speed) {
        $Doom::Info::MOBJINFO[$mt][15] = $want ? $shot_speed{$mt} * 2 : $shot_speed{$mt};
    }
    return;
}

sub nightmare {
    my ($world, $mo) = @_;
    return if !$world->{respawn} || !$mo || $mo->{player};
    return if !(($mo->{flags} || 0) & MF_COUNTKILL);
    $mo->{movecount} = ($mo->{movecount} || 0) + 1;
    return if $mo->{movecount} < 12 * 35;
    return if ($world->{leveltime} || 0) & 31;
    return if Doom::Attack::p_random() > 4;
    my $x = defined $mo->{spawnx} ? $mo->{spawnx} : $mo->{x};
    my $y = defined $mo->{spawny} ? $mo->{spawny} : $mo->{y};
    my $chk = Doom::Collision::check_position($world, $mo, $x, $y);
    return if $chk->{blocked};
    Doom::Attack::_spawn_fx($world, $mo->{x}, $mo->{y}, $mo->{floorz} || $mo->{z}, 39);
    Doom::Sound::at($world, 'telept');
    my $sub = $world->point_in_subsector($x, $y);
    my $z = $sub && $sub->{sector} ? $sub->{sector}{floorheight} : ($mo->{z} || 0);
    Doom::Attack::_spawn_fx($world, $x, $y, $z, 39);
    my $born = _spawn_at($world, $x, $y, $z, $mo->{type});
    return if !$born;
    $born->{angle} = $mo->{spawnang} || 0;
    $born->{spawnx} = $x;
    $born->{spawny} = $y;
    $born->{spawnang} = $born->{angle};
    $born->{flags} |= 32 if ($mo->{spawnopt} || 0) & 8;
    $born->{reactiontime} = 18;
    Doom::Attack::_remove($world, $mo);
    return;
}

sub tick_skull {
    my ($world, $mo) = @_;
    return if !$mo || !(($mo->{flags} || 0) & MF_SKULLFLY);
    if (!($mo->{momx} || 0) && !($mo->{momy} || 0)) {
        _skull_stop($world, $mo);
        return;
    }
    $mo->{z} += $mo->{momz} || 0;
    if (!try_move($world, $mo, $mo->{x} + $mo->{momx}, $mo->{y} + $mo->{momy})) {
        my $hit = $mo->{_hitthing};
        if ($hit && (($hit->{flags} || 0) & MF_SHOOTABLE) && $hit != $mo) {
            my $info = _info($mo) || [];
            my $dmg = ($info->[MI_DAMAGE] || 3) * ((Doom::Attack::p_random() % 8) + 1);
            Doom::Attack::damage_mobj($world, $hit, $mo, $dmg);
        }
        _skull_stop($world, $mo);
        return;
    }
    if ($mo->{z} <= ($mo->{floorz} || 0) || $mo->{z} + ($mo->{height} || 0) > ($mo->{ceilingz} || 0)) {
        _skull_stop($world, $mo);
    }
    return;
}

sub _skull_stop {
    my ($world, $mo) = @_;
    $mo->{flags} &= ~MF_SKULLFLY;
    $mo->{momx} = $mo->{momy} = $mo->{momz} = 0;
    my $info = _info($mo);
    Doom::Attack::set_mobj_state($world, $mo, $info->[1] || 0) if $info;
    return;
}

sub _skull_attack {
    my ($world, $mo) = @_;
    my $dest = $mo->{target};
    return if !$dest;
    $mo->{flags} |= MF_SKULLFLY;
    Doom::Sound::at($world, 'sklatk');
    _face($mo, $dest);
    $mo->{momx} = fixed_mul(SKULLSPEED, fine_cos($mo->{angle}));
    $mo->{momy} = fixed_mul(SKULLSPEED, fine_sin($mo->{angle}));
    my $dist = approx_distance($dest->{x} - $mo->{x}, $dest->{y} - $mo->{y});
    my $steps = int($dist / SKULLSPEED);
    $steps = 1 if $steps < 1;
    $mo->{momz} = int((($dest->{z} || 0) + int(($dest->{height} || 0) / 2) - $mo->{z}) / $steps);
    return;
}

sub _ball {
    my ($world, $mo, $type) = @_;
    return if !$mo->{target};
    _face($mo, $mo->{target});
    return _spawn_ball($world, $mo, $mo->{target}, $type);
}

sub _refire {
    my ($world, $mo, $chance) = @_;
    _face($mo, $mo->{target}) if $mo->{target};
    return if Doom::Attack::p_random() < $chance;
    my $t = $mo->{target};
    if (!$t || ($t->{health} || 0) <= 0 || !_sight($world, $mo, $t)) {
        my $info = _info($mo);
        Doom::Attack::set_mobj_state($world, $mo, $info->[3] || 0) if $info;
    }
    return;
}

sub _pain_shoot {
    my ($world, $actor, $ang) = @_;
    my $n = 0;
    for my $other (@{$world->{mobjs} || []}) {
        $n++ if $other && ($other->{type} || 0) == 18 && ($other->{health} || 0) > 0;
    }
    return if $n >= MAXSKULLS;
    my $pre = 4 * FRACUNIT + int(3 * ($actor->{radius} || 0) / 2);
    my $x = $actor->{x} + fixed_mul($pre, fine_cos($ang));
    my $y = $actor->{y} + fixed_mul($pre, fine_sin($ang));
    my $skull = _spawn_at($world, $x, $y, $actor->{z}, 18);
    return if !$skull;
    $skull->{angle} = $ang;
    my $chk = Doom::Collision::check_position($world, $skull, $skull->{x}, $skull->{y});
    if ($chk->{blocked}) {
        Doom::Attack::damage_mobj($world, $skull, $actor, 10000);
        return;
    }
    $skull->{target} = $actor->{target};
    _skull_attack($world, $skull);
    return;
}

sub _fat {
    my ($world, $mo, $which) = @_;
    return if !$mo->{target};
    _face($mo, $mo->{target});
    my $spread = FATSPREAD;
    $spread = -$spread if $which == 2;
    $mo->{angle} = as_u32($mo->{angle} + $spread) if $which != 3;
    my $a = _spawn_ball($world, $mo, $mo->{target}, 9);
    my $b = _spawn_ball($world, $mo, $mo->{target}, 9);
    return if !$b;
    my $turn = $which == 1 ? FATSPREAD : $which == 2 ? -(FATSPREAD * 2) : int(FATSPREAD / 2);
    $b->{angle} = as_u32(($which == 3 ? $mo->{angle} : $b->{angle}) + $turn);
    my $info = $Doom::Info::MOBJINFO[9];
    my $speed = $info ? $info->[15] : 0;
    $b->{momx} = fixed_mul($speed, fine_cos($b->{angle}));
    $b->{momy} = fixed_mul($speed, fine_sin($b->{angle}));
    if ($which == 3 && $a) {
        $a->{angle} = as_u32($mo->{angle} - int(FATSPREAD / 2));
        $a->{momx} = fixed_mul($speed, fine_cos($a->{angle}));
        $a->{momy} = fixed_mul($speed, fine_sin($a->{angle}));
    }
    return;
}

sub _tracer_home {
    my ($mo) = @_;
    my $dest = $mo->{tracer};
    return if !$dest || ($dest->{health} || 0) <= 0;
    my $exact = Doom::Collision::angle_to($mo->{x}, $mo->{y}, $dest->{x}, $dest->{y});
    my $diff = as_u32($exact - ($mo->{angle} || 0));
    if ($diff > 0x80000000) {
        $mo->{angle} = as_u32($mo->{angle} - TRACEANGLE);
        $mo->{angle} = $exact if as_u32($exact - $mo->{angle}) < 0x80000000;
    }
    else {
        $mo->{angle} = as_u32($mo->{angle} + TRACEANGLE);
        $mo->{angle} = $exact if as_u32($exact - $mo->{angle}) > 0x80000000;
    }
    my $info = _info($mo) || [];
    my $speed = $info->[15] || 0;
    $mo->{momx} = fixed_mul($speed, fine_cos($mo->{angle}));
    $mo->{momy} = fixed_mul($speed, fine_sin($mo->{angle}));
    my $dist = approx_distance($dest->{x} - $mo->{x}, $dest->{y} - $mo->{y});
    my $steps = $speed ? int($dist / $speed) : 1;
    $steps = 1 if $steps < 1;
    $mo->{momz} = int((($dest->{z} || 0) + 40 * FRACUNIT - $mo->{z}) / $steps);
    return;
}

sub _vile_chase {
    my ($world, $mo) = @_;
    for my $other (@{$world->{mobjs} || []}) {
        next if !$other || $other == $mo;
        next if !(($other->{flags} || 0) & MF_CORPSE);
        next if ($other->{health} || 0) > 0;
        my $info = _info($other);
        next if !$info || !($info->[22] || 0);
        my $max = ($mo->{radius} || 0) + ($other->{radius} || 0);
        next if abs($other->{x} - $mo->{x}) > $max || abs($other->{y} - $mo->{y}) > $max;
        Doom::Attack::set_mobj_state($world, $mo, 266);
        Doom::Sound::at($world, 'slop');
        Doom::Attack::set_mobj_state($world, $other, $info->[22]);
        $other->{flags} = $info->[21];
        $other->{health} = $info->[2];
        $other->{height} = $info->[17];
        $other->{radius} = $info->[16];
        $other->{target} = undef;
        $other->{alive} = 1;
        $other->{z} = $other->{floorz} || $other->{z};
        return 1;
    }
    return 0;
}

sub _vile_attack {
    my ($world, $mo) = @_;
    my $dest = $mo->{target};
    return if !$dest || !_sight($world, $mo, $dest);
    Doom::Sound::at($world, 'vilatk');
    Doom::Attack::damage_mobj($world, $dest, $mo, 20);
    for my $th (@{$world->{mobjs} || []}) {
        next if !$th || $th == $mo || !$th->{alive};
        next if !(($th->{flags} || 0) & MF_SHOOTABLE);
        my $dist = approx_distance($th->{x} - $dest->{x}, $th->{y} - $dest->{y});
        my $dmg = 70 - int($dist / FRACUNIT);
        Doom::Attack::damage_mobj($world, $th, $mo, $dmg) if $dmg > 0;
    }
    return;
}

sub _vile_target {
    my ($world, $mo) = @_;
    return if !$mo->{target};
    _face($mo, $mo->{target});
    my $fog = _spawn_at($world, $mo->{target}{x}, $mo->{target}{y}, $mo->{target}{z}, 4);
    return if !$fog;
    $mo->{tracer} = $fog;
    $fog->{target} = $mo;
    $fog->{tracer} = $mo->{target};
    return;
}

sub _fire_follow {
    my ($mo) = @_;
    my $dest = $mo->{tracer};
    return if !$dest || !$mo->{target};
    $mo->{x} = $dest->{x};
    $mo->{y} = $dest->{y};
    $mo->{z} = $dest->{z};
    return;
}

sub _boss_death {
    my ($world, $mo, $keen) = @_;
    my $type = $mo->{type} || 0;
    for my $other (@{$world->{mobjs} || []}) {
        next if !$other || $other == $mo;
        return if ($other->{type} || 0) == $type && ($other->{health} || 0) > 0;
    }
    my $spec = $world->{specials};
    return if !$spec;
    if ($keen) {
        $spec->_door_tag({ tag => 666 }, 6);
        return;
    }
    my $map = $world->{mapn} || 1;
    my $ep = $world->{episode} || 1;
    if ($world->{commercial}) {
        return if $map != 7;
        $spec->boss_floor(666) if $type == 8;
        $spec->boss_raise(667) if $type == 20;
        return;
    }
    if ($ep == 1 && $map == 8 && $type == 15) {
        $spec->boss_floor(666);
    }
    elsif (($ep == 2 && $map == 8 && $type == 21) || ($ep == 3 && $map == 8 && $type == 19)) {
        $spec->{exit} = 1;
    }
    elsif (($ep == 4 && $map == 6 && $type == 21) || ($ep == 4 && $map == 8 && $type == 15)) {
        $spec->boss_floor(666);
    }
    return;
}

sub _brain_spit {
    my ($world, $actor) = @_;
    if (($world->{skill} || 0) <= 1) {
        $actor->{_easy} = !$actor->{_easy};
        return if $actor->{_easy};
    }
    @brain = grep { ($_->{type} || 0) == 27 } @{$world->{mobjs} || []} if !@brain;
    return if !@brain;
    my $dest = $brain[$brain_on % @brain];
    $brain_on++;
    Doom::Sound::at($world, 'bospit');
    my $miss = _spawn_ball($world, $actor, $dest, 28);
    return if !$miss;
    $miss->{target} = $dest;
    my $st = $miss->{tics} || 1;
    $miss->{reactiontime} = int((($dest->{y} - $actor->{y}) / $miss->{momy}) / $st) if $miss->{momy};
    return;
}

sub _spawn_fly {
    my ($world, $cube) = @_;
    $cube->{reactiontime} = ($cube->{reactiontime} || 0) - 1;
    return if ($cube->{reactiontime} || 0) != 0;
    my $dest = $cube->{target} || $cube;
    my $r = Doom::Attack::p_random();
    my $typ = $r < 50 ? 11 : $r < 90 ? 12 : $r < 120 ? 13 : $r < 130 ? 22
        : $r < 160 ? 14 : $r < 162 ? 3 : $r < 172 ? 5 : $r < 192 ? 20
        : $r < 222 ? 8 : $r < 246 ? 17 : 15;
    Doom::Sound::at($world, 'telept');
    my $born = _spawn_at($world, $dest->{x}, $dest->{y}, $dest->{z}, $typ);
    $born->{angle} = $dest->{angle} || 0 if $born;
    Doom::Attack::_remove($world, $cube);
    return;
}

sub _spawn_at {
    my ($world, $x, $y, $z, $type) = @_;
    my $info = $Doom::Info::MOBJINFO[$type];
    return if !$info;
    my $stn = $info->[1];
    my $st = $Doom::Info::STATES[$stn];
    return if !$st;
    my $sub = $world->point_in_subsector($x, $y);
    my $mo = {
        x => $x, y => $y, z => $z, angle => 0,
        radius => $info->[16], height => $info->[17],
        floorz => $sub && $sub->{sector} ? $sub->{sector}{floorheight} : $z,
        ceilingz => $sub && $sub->{sector} ? $sub->{sector}{ceilingheight} : $z,
        flags => $info->[21], health => $info->[2], type => $type,
        doomednum => $info->[0], player => undef, alive => 1,
        istate => $stn, tics => $st->[2],
        sprite => sprite_name($st->[0]), frame => $st->[1],
        momx => 0, momy => 0, momz => 0,
        movedir => 8, movecount => 0, reactiontime => $info->[5] || 0,
    };
    push @{$world->{mobjs}}, $mo;
    Doom::Collision::set_thing_position($world, $mo);
    return $mo;
}

1;
