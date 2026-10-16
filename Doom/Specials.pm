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
# A porta manual sobe e desce. O interruptor muda de imagem.
# O piso desce e o elevador sobe. O lodo fere e a luz pisca.
# O interruptor abre a porta e o elevador. O tiro na parede abre caminho.
# Igual a doom/specials.py.

package Doom::Specials;

use strict;
use warnings;

use Doom::Attack ();
use Doom::Collision qw(change_sector);
use Doom::Compat qw(fixed_mul);
use Doom::Defs qw(FRACUNIT ML_TWOSIDED);
use Doom::Sound ();
use Doom::Tables qw(fine_cos fine_sin);

use constant VDOORSPEED    => 2 * FRACUNIT;
use constant VDOORWAIT     => 150;
use constant TICRATE       => 35;
use constant VLD_NORMAL    => 0;
use constant VLD_CLOSE30   => 1;
use constant VLD_CLOSE     => 2;
use constant VLD_OPEN      => 3;
use constant VLD_RAISEIN5  => 4;
use constant VLD_BLAZERAISE => 5;
use constant VLD_BLAZEOPEN => 6;
use constant VLD_BLAZECLOSE => 7;
use constant MF_MISSILE => 0x10000;
use constant MT_TFOG => 39;
use constant RESULT_PASTDEST => 2;
use constant IT_BLUECARD   => 0;
use constant IT_YELLOWCARD => 1;
use constant IT_REDCARD    => 2;
use constant IT_BLUESKULL  => 3;
use constant IT_YELLOWSKULL => 4;
use constant IT_REDSKULL   => 5;

my @SWITCHES = (
    [qw(SW1BRCOM SW2BRCOM)], [qw(SW1BRN1 SW2BRN1)], [qw(SW1BRN2 SW2BRN2)],
    [qw(SW1BRNGN SW2BRNGN)], [qw(SW1BROWN SW2BROWN)], [qw(SW1COMM SW2COMM)],
    [qw(SW1COMP SW2COMP)], [qw(SW1DIRT SW2DIRT)], [qw(SW1EXIT SW2EXIT)],
    [qw(SW1GRAY SW2GRAY)], [qw(SW1GRAY1 SW2GRAY1)], [qw(SW1METAL SW2METAL)],
    [qw(SW1PIPE SW2PIPE)], [qw(SW1SLAD SW2SLAD)], [qw(SW1STARG SW2STARG)],
    [qw(SW1STON1 SW2STON1)], [qw(SW1STON2 SW2STON2)], [qw(SW1STONE SW2STONE)],
    [qw(SW1STRTN SW2STRTN)], [qw(SW1BLUE SW2BLUE)], [qw(SW1CMT SW2CMT)],
    [qw(SW1GARG SW2GARG)], [qw(SW1GSTON SW2GSTON)], [qw(SW1HOT SW2HOT)],
    [qw(SW1LION SW2LION)], [qw(SW1SATYR SW2SATYR)], [qw(SW1SKIN SW2SKIN)],
    [qw(SW1VINE SW2VINE)], [qw(SW1WOOD SW2WOOD)], [qw(SW1PANEL SW2PANEL)],
    [qw(SW1ROCK SW2ROCK)], [qw(SW1MET2 SW2MET2)], [qw(SW1WDMET SW2WDMET)],
    [qw(SW1BRIK SW2BRIK)], [qw(SW1MOD1 SW2MOD1)], [qw(SW1ZIM SW2ZIM)],
    [qw(SW1STON6 SW2STON6)], [qw(SW1TEK SW2TEK)], [qw(SW1MARB SW2MARB)],
    [qw(SW1SKULL SW2SKULL)],
);

use constant FLOORSPEED => FRACUNIT;
use constant PLAT_DOWN => 0;
use constant PLAT_UP => 1;
use constant PLAT_WAIT => 2;
use constant GLOWSPEED => 8;
use constant STROBEBRIGHT => 5;
use constant FASTDARK => 15;
use constant SLOWDARK => 35;

sub new {
    my ($class, $world, $res) = @_;
    my $self = bless {
        world => $world, thinkers => [], buttons => [], switch => {},
        lights => [], scroll => [], exit => 0, time => 0,
    }, $class;
    if ($res) {
        for my $pair (@SWITCHES) {
            my $a = $res->texture_num_for_name($pair->[0]);
            my $b = $res->texture_num_for_name($pair->[1]);
            next if !$a && !$b;
            $self->{switch}{$a} = $b;
            $self->{switch}{$b} = $a;
        }
    }
    $self->_spawn_specials;
    return $self;
}

sub tick {
    my ($self) = @_;
    $self->_tick_lights;
    for my $ln (@{$self->{scroll}}) {
        my $side = $ln->{sides}[0];
        $side->{textureoffset} += FRACUNIT if $side;
    }
    my @alive;
    for my $th (@{$self->{thinkers}}) {
        my $kind = $th->{kind} || 'door';
        $self->_tick_door($th) if $kind eq 'door';
        $self->_tick_floor($th) if $kind eq 'floor';
        $self->_tick_plat($th) if $kind eq 'plat';
        push @alive, $th if !$th->{dead};
    }
    $self->{thinkers} = \@alive;
    my @buttons;
    for my $b (@{$self->{buttons}}) {
        if (--$b->{timer} <= 0) {
            my $side = $b->{line}{sides}[0];
            $side->{$b->{where}} = $b->{texture} if $side;
        }
        else {
            push @buttons, $b;
        }
    }
    $self->{buttons} = \@buttons;
    return;
}

sub use_special {
    my ($self, $line, $thing, $side) = @_;
    return 0 if $side;
    my $spec = $line->{special};
    if ($spec == 1 || ($spec >= 26 && $spec <= 28)
        || ($spec >= 31 && $spec <= 34) || $spec == 117 || $spec == 118)
    {
        $self->vertical_door($line, $thing);
        return 1;
    }
    if ($spec == 11 || $spec == 51) {
        $self->change_switch($line, 0);
        $self->{exit} = 1;
        $self->{secret} = 1 if $spec == 51;
        return 1;
    }
    if ($spec == 103) {
        return 0 if !$self->_door_tag($line, VLD_OPEN);
        $self->change_switch($line, 0);
        return 1;
    }
    if ($spec == 114) {
        return 0 if !$self->_door_tag($line, VLD_BLAZERAISE);
        $self->change_switch($line, 1);
        return 1;
    }
    if ($spec == 102) {
        return 0 if !$self->_floor($line, -1, FLOORSPEED);
        $self->change_switch($line, 0);
        return 1;
    }
    if ($spec >= 133 && $spec <= 137) {
        $self->_locked_blaze($line, $thing, $spec);
        return 1;
    }
    if ($spec == 62) {
        $self->change_switch($line, 1) if $self->_plat($line);
        return 1;
    }
    if ($spec == 9) {
        $self->change_switch($line, 0) if $self->_donut($line);
        return 1;
    }
    return 0;
}

sub shoot_special {
    my ($self, $line, $thing) = @_;
    return if ($line->{special} || 0) != 46;
    $self->_door_tag($line, VLD_OPEN);
    $self->change_switch($line, 1);
    return;
}

sub cross_special {
    my ($self, $line, $side, $thing) = @_;
    my $spec = $line->{special} || 0;
    my $clear = 1;
    if ($spec == 36) {
        $self->_floor($line, -1, FLOORSPEED * 4);
    }
    elsif ($spec == 88) {
        $self->_plat($line);
        $clear = 0;
    }
    elsif ($spec == 108 || $spec == 109 || $spec == 110) {
        my $type = $spec == 108 ? VLD_BLAZERAISE
            : $spec == 110 ? VLD_BLAZECLOSE : VLD_BLAZEOPEN;
        $self->_door_tag($line, $type);
    }
    elsif ($spec == 8) {
        return if !$thing->{player};
        $self->_stairs($line, 8 * FRACUNIT, int(FLOORSPEED / 4) || 1);
    }
    elsif ($spec == 2 || $spec == 3 || $spec == 4) {
        return if $spec != 4 && !$thing->{player};
        my $type = $spec == 2 ? VLD_OPEN : $spec == 3 ? VLD_CLOSE : VLD_NORMAL;
        $self->_door_tag($line, $type);
    }
    elsif ($spec == 39 || $spec == 97) {
        my $ok = $self->_teleport($line, $side, $thing);
        $clear = 0 if $spec == 97 || !$ok;
    }
    else {
        return;
    }
    $line->{special} = 0 if $clear;
    return;
}

sub _teleport {
    my ($self, $line, $side, $thing) = @_;
    return 0 if ($side || 0) != 0 || !$thing;
    return 0 if ($thing->{flags} || 0) & MF_MISSILE;
    my $tag = $line->{tag} || 0;
    return 0 if !$tag;
    my $world = $self->{world};
    my $sectors = $world->{sectors} || [];
    for my $i (0 .. $#$sectors) {
        my $sector = $sectors->[$i];
        next if ($sector->{tag} || 0) != $tag;
        for my $dest (@{$world->{mobjs} || []}) {
            next if !$dest || !$dest->{alive} || ($dest->{doomednum} || 0) != 14;
            my $sub = $world->point_in_subsector($dest->{x}, $dest->{y});
            my $dsec = $sub && $sub->{sector};
            next if !$dsec;
            next if $dsec != $sector && ($dsec->{i_sector} // -1) != $i;
            my ($oldx, $oldy, $oldz) = ($thing->{x}, $thing->{y}, $thing->{z});
            $thing->{momx} = 0;
            $thing->{momy} = 0;
            $thing->{momz} = 0;
            $thing->{_stopmove} = 1;
            Doom::Collision::unset_thing_position($world, $thing);
            $thing->{x} = $dest->{x};
            $thing->{y} = $dest->{y};
            $thing->{floorz} = $dsec->{floorheight};
            $thing->{ceilingz} = $dsec->{ceilingheight};
            $thing->{z} = $thing->{floorz};
            $thing->{angle} = $dest->{angle} || 0;
            $thing->{reactiontime} = 18 if $thing->{player};
            Doom::Collision::set_thing_position($world, $thing);
            _fog($world, $oldx, $oldy, $oldz);
            my $ang = $thing->{angle};
            _fog(
                $world,
                $thing->{x} + fixed_mul(20 * FRACUNIT, fine_cos($ang)),
                $thing->{y} + fixed_mul(20 * FRACUNIT, fine_sin($ang)),
                $thing->{z},
            );
            Doom::Sound::at($world, 'telept');
            return 1;
        }
    }
    return 0;
}

sub _fog {
    my ($world, $x, $y, $z) = @_;
    Doom::Attack::_spawn_fx($world, $x, $y, $z || 0, MT_TFOG);
    return;
}

sub change_switch {
    my ($self, $line, $again) = @_;
    my $side = $line->{sides}[0];
    return if !$side;
    $line->{special} = 0 if !$again;
    my $sound = ($line->{special} || 0) == 11 ? 'swtchx' : 'swtchn';
    for my $where (qw(top mid bottom)) {
        my $key = $where . 'texture';
        my $tex = $side->{$key} || 0;
        next if !exists $self->{switch}{$tex};
        if ($again) {
            push @{$self->{buttons}}, {
                line => $line, where => $key, texture => $tex, timer => TICRATE,
            };
        }
        $side->{$key} = $self->{switch}{$tex};
        Doom::Sound::at($self->{world}, $sound);
        return;
    }
    Doom::Sound::at($self->{world}, $sound);
    return;
}

sub hurt_sector {
    my ($self, $mo) = @_;
    my $time = $self->{time} || 0;
    $self->{time} = $time + 1;
    return if !$mo;
    my $sec = $self->{world}->point_in_subsector($mo->{x}, $mo->{y})->{sector};
    return if ($mo->{z} || 0) != ($sec->{floorheight} || 0) || !$sec->{special};
    if ($sec->{special} == 9) {
        $sec->{special} = 0;
        $mo->{secrets} = ($mo->{secrets} || 0) + 1;
        print "segredo\n";
        return;
    }
    return if $sec->{special} != 5 && $sec->{special} != 7 && $sec->{special} != 4
        && $sec->{special} != 16 && $sec->{special} != 11;
    return if ($mo->{pow_suit} || 0) > 0 && $sec->{special} != 11;
    return if ($time & 0x1f) != 0;
    my $damage = $sec->{special} == 7 ? 5 : ($sec->{special} == 5 ? 10 : 20);
    Doom::Attack::damage_mobj($self->{world}, $mo, undef, $damage);
    $self->{exit} = 1 if $sec->{special} == 11 && ($mo->{health} || 0) <= 10;
    return;
}

sub _spawn_specials {
    my ($self) = @_;
    for my $sector (@{$self->{world}{sectors}}) {
        my $spec = $sector->{special} || 0;
        $self->_light_flash($sector) if $spec == 1;
        $self->_light_strobe($sector, FASTDARK, 0) if $spec == 2;
        $self->_light_strobe($sector, SLOWDARK, 0) if $spec == 3;
        if ($spec == 4) {
            $self->_light_strobe($sector, FASTDARK, 0);
            $sector->{special} = 4;
        }
        $self->_light_glow($sector) if $spec == 8;
        $self->_light_strobe($sector, SLOWDARK, 1) if $spec == 12;
        $self->_light_strobe($sector, FASTDARK, 1) if $spec == 13;
        $self->_light_fire($sector) if $spec == 17;
    }
    for my $ln (@{$self->{world}{lines} || []}) {
        push @{$self->{scroll}}, $ln if ($ln->{special} || 0) == 48;
    }
    return;
}

sub _min_light {
    my ($sector, $max) = @_;
    for my $other (surrounding_sectors($sector)) {
        $max = $other->{lightlevel} if $other->{lightlevel} < $max;
    }
    return $max;
}

sub _light_flash {
    my ($self, $sector) = @_;
    $sector->{special} = 0;
    my $light = {
        kind => 'flash', sector => $sector,
        maxlight => $sector->{lightlevel},
        minlight => _min_light($sector, $sector->{lightlevel}),
        maxtime => 64, mintime => 7, count => 0,
    };
    $light->{count} = (Doom::Attack::p_random() & $light->{maxtime}) + 1;
    push @{$self->{lights}}, $light;
    return;
}

sub _light_strobe {
    my ($self, $sector, $dark, $sync) = @_;
    $sector->{special} = 0;
    my $min = _min_light($sector, $sector->{lightlevel});
    $min = 0 if $min == $sector->{lightlevel};
    push @{$self->{lights}}, {
        kind => 'strobe', sector => $sector,
        maxlight => $sector->{lightlevel}, minlight => $min,
        darktime => $dark, brighttime => STROBEBRIGHT,
        count => $sync ? 1 : (Doom::Attack::p_random() & 7) + 1,
    };
    return;
}

sub _light_glow {
    my ($self, $sector) = @_;
    $sector->{special} = 0;
    push @{$self->{lights}}, {
        kind => 'glow', sector => $sector, direction => -1,
        maxlight => $sector->{lightlevel},
        minlight => _min_light($sector, $sector->{lightlevel}),
    };
    return;
}

sub _light_fire {
    my ($self, $sector) = @_;
    $sector->{special} = 0;
    push @{$self->{lights}}, {
        kind => 'fire', sector => $sector, count => 4,
        maxlight => $sector->{lightlevel},
        minlight => _min_light($sector, $sector->{lightlevel}),
    };
    return;
}

sub _tick_lights {
    my ($self) = @_;
    for my $light (@{$self->{lights}}) {
        my $sector = $light->{sector};
        if ($light->{kind} eq 'glow') {
            if ($light->{direction} == -1) {
                $sector->{lightlevel} -= GLOWSPEED;
                if ($sector->{lightlevel} <= $light->{minlight}) {
                    $sector->{lightlevel} += GLOWSPEED;
                    $light->{direction} = 1;
                }
            }
            else {
                $sector->{lightlevel} += GLOWSPEED;
                if ($sector->{lightlevel} >= $light->{maxlight}) {
                    $sector->{lightlevel} -= GLOWSPEED;
                    $light->{direction} = -1;
                }
            }
            next;
        }
        $light->{count}--;
        next if $light->{count} != 0;
        if ($light->{kind} eq 'flash') {
            if ($sector->{lightlevel} == $light->{maxlight}) {
                $sector->{lightlevel} = $light->{minlight};
                $light->{count} = (Doom::Attack::p_random() & $light->{mintime}) + 1;
            }
            else {
                $sector->{lightlevel} = $light->{maxlight};
                $light->{count} = (Doom::Attack::p_random() & $light->{maxtime}) + 1;
            }
        }
        elsif ($light->{kind} eq 'strobe') {
            if ($sector->{lightlevel} == $light->{minlight}) {
                $sector->{lightlevel} = $light->{maxlight};
                $light->{count} = $light->{brighttime};
            }
            else {
                $sector->{lightlevel} = $light->{minlight};
                $light->{count} = $light->{darktime};
            }
        }
        elsif ($light->{kind} eq 'fire') {
            my $amount = (Doom::Attack::p_random() & 3) * 16;
            my $next = $sector->{lightlevel} - $amount;
            $sector->{lightlevel} = $next < $light->{minlight}
                ? $light->{minlight} : $light->{maxlight} - $amount;
            $light->{count} = 4;
        }
    }
    return;
}

sub vertical_door {
    my ($self, $line, $thing) = @_;
    my $spec = $line->{special};
    if ($thing->{player}) {
        if (($spec == 26 || $spec == 32) && !_has_key($thing, IT_BLUECARD, IT_BLUESKULL)) {
            print "falta a chave azul\n";
            Doom::Sound::at($self->{world}, 'oof');
            return;
        }
        if (($spec == 27 || $spec == 34) && !_has_key($thing, IT_YELLOWCARD, IT_YELLOWSKULL)) {
            print "falta a chave amarela\n";
            Doom::Sound::at($self->{world}, 'oof');
            return;
        }
        if (($spec == 28 || $spec == 33) && !_has_key($thing, IT_REDCARD, IT_REDSKULL)) {
            print "falta a chave vermelha\n";
            Doom::Sound::at($self->{world}, 'oof');
            return;
        }
    }
    my $side = $line->{sides}[1];
    return if !$side || !$side->{sector};
    my $dtype = VLD_NORMAL;
    if ($spec >= 31 && $spec <= 34) {
        $dtype = VLD_OPEN;
        $line->{special} = 0;
    }
    elsif ($spec == 117) {
        $dtype = VLD_BLAZERAISE;
    }
    elsif ($spec == 118) {
        $dtype = VLD_BLAZEOPEN;
        $line->{special} = 0;
    }
    $self->_spawn_door($side->{sector}, $dtype);
    return;
}

sub _has_key {
    my ($thing, $card, $skull) = @_;
    my $cards = $thing->{cards};
    return $cards && ($cards->[$card] || $cards->[$skull]) ? 1 : 0;
}

sub _locked_blaze {
    my ($self, $line, $thing, $spec) = @_;
    return if !$thing->{player};
    my ($card, $skull, $name);
    if ($spec == 99 || $spec == 133) {
        ($card, $skull, $name) = (IT_BLUECARD, IT_BLUESKULL, 'azul');
    }
    elsif ($spec == 134 || $spec == 135) {
        ($card, $skull, $name) = (IT_REDCARD, IT_REDSKULL, 'vermelha');
    }
    else {
        ($card, $skull, $name) = (IT_YELLOWCARD, IT_YELLOWSKULL, 'amarela');
    }
    if (!_has_key($thing, $card, $skull)) {
        print "falta a chave $name\n";
        Doom::Sound::at($self->{world}, 'oof');
        return;
    }
    my $again = ($spec == 99 || $spec == 134 || $spec == 136) ? 1 : 0;
    $self->change_switch($line, $again) if $self->_door_tag($line, VLD_BLAZEOPEN);
    return;
}

sub _spawn_door {
    my ($self, $sector, $dtype) = @_;
    if ($sector->{specialdata}) {
        my $door = $sector->{specialdata};
        if ($door->{kind} && $door->{kind} eq 'door'
            && ($dtype == VLD_NORMAL || $dtype == VLD_BLAZERAISE))
        {
            $door->{direction} = $door->{direction} == -1 ? 1 : -1;
            $self->_door_noise($door, $door->{direction} == 1);
            return 1;
        }
        return 0;
    }
    my $top = lowest_ceiling($sector) - 4 * FRACUNIT;
    $top = $sector->{ceilingheight} if $dtype == VLD_CLOSE30;
    my $down = $dtype == VLD_CLOSE || $dtype == VLD_BLAZECLOSE || $dtype == VLD_CLOSE30;
    my $door = {
        kind => 'door',
        sector => $sector,
        type => $dtype,
        direction => $down ? -1 : 1,
        topheight => $top,
        speed => VDOORSPEED * ($dtype >= VLD_BLAZERAISE ? 4 : 1),
        topwait => VDOORWAIT,
        topcountdown => 0,
        dead => 0,
    };
    $sector->{specialdata} = $door;
    push @{$self->{thinkers}}, $door;
    $self->_door_noise($door, $door->{direction} == 1);
    return 1;
}

sub _door_noise {
    my ($self, $door, $up) = @_;
    my $blaze = ($door->{type} || 0) >= VLD_BLAZERAISE;
    Doom::Sound::at($self->{world}, $up ? ($blaze ? 'bdopn' : 'doropn') : ($blaze ? 'bdcls' : 'dorcls'));
    return;
}

sub _tick_door {
    my ($self, $door) = @_;
    if ($door->{direction} == 0) {
        $door->{topcountdown}--;
        return if $door->{topcountdown} > 0;
        if ($door->{type} == VLD_NORMAL || $door->{type} == VLD_BLAZERAISE || $door->{type} == VLD_CLOSE) {
            $door->{direction} = -1;
            $self->_door_noise($door, 0);
        }
        elsif ($door->{type} == VLD_CLOSE30 || $door->{type} == VLD_RAISEIN5) {
            $door->{direction} = 1;
        }
        return;
    }
    my $dest = $door->{direction} == 1 ? $door->{topheight} : $door->{sector}{floorheight};
    my $res = move_plane(
        $self->{world}, $door->{sector}, $door->{speed}, $dest, 1, $door->{direction}
    );
    return if $res != RESULT_PASTDEST;
    if ($door->{direction} == 1) {
        if ($door->{type} == VLD_NORMAL || $door->{type} == VLD_BLAZERAISE) {
            $door->{direction} = 0;
            $door->{topcountdown} = $door->{topwait};
        }
        else {
            $door->{sector}{specialdata} = undef;
            $door->{dead} = 1;
        }
        return;
    }
    if ($door->{type} == VLD_CLOSE30) {
        $door->{direction} = 0;
        $door->{topcountdown} = TICRATE * 30;
        return;
    }
    $door->{sector}{specialdata} = undef;
    $door->{dead} = 1;
    return;
}

sub _tagged {
    my ($self, $tag) = @_;
    return if !$tag;
    return grep { ($_->{tag} || 0) == $tag } @{$self->{world}{sectors}};
}

sub _highest_floor {
    my ($sector) = @_;
    my $h = -500 * FRACUNIT;
    for my $other (surrounding_sectors($sector)) {
        $h = $other->{floorheight} if $other->{floorheight} > $h;
    }
    return $h;
}

sub _lowest_floor {
    my ($sector) = @_;
    my $h = $sector->{floorheight};
    for my $other (surrounding_sectors($sector)) {
        $h = $other->{floorheight} if $other->{floorheight} < $h;
    }
    return $h;
}

sub _start_floor {
    my ($self, $sector, $dest, $dir, $speed, $pic) = @_;
    return 0 if !$sector || $sector->{specialdata};
    my $move = {
        kind => 'floor', sector => $sector, direction => $dir,
        dest => $dest, speed => $speed, dead => 0, pic => $pic,
    };
    $sector->{specialdata} = $move;
    push @{$self->{thinkers}}, $move;
    return 1;
}

sub _stairs {
    my ($self, $line, $step, $speed) = @_;
    my $ok = 0;
    for my $sec ($self->_tagged($line->{tag})) {
        next if $sec->{specialdata};
        my $height = ($sec->{floorheight} || 0) + $step;
        next if !$self->_start_floor($sec, $height, 1, $speed);
        $ok = 1;
        my $texture = $sec->{floorpic};
        my $cur = $sec;
        while (1) {
            my $nxt;
            for my $ln (@{$cur->{lines} || []}) {
                next if !(($ln->{flags} || 0) & ML_TWOSIDED);
                my $other = ($ln->{frontsector} && $ln->{frontsector} == $cur)
                    ? $ln->{backsector} : $ln->{frontsector};
                next if !$other || $other == $cur;
                next if ($other->{floorpic} || 0) != ($texture || 0) || $other->{specialdata};
                $nxt = $other;
                last;
            }
            last if !$nxt;
            $height += $step;
            last if !$self->_start_floor($nxt, $height, 1, $speed);
            $cur = $nxt;
        }
    }
    return $ok;
}

sub _floor {
    my ($self, $line, $dir, $speed) = @_;
    my $ok = 0;
    for my $sector ($self->_tagged($line->{tag})) {
        $ok = 1 if $self->_start_floor($sector, _highest_floor($sector), $dir, $speed);
    }
    return $ok;
}

sub _door_tag {
    my ($self, $line, $dtype) = @_;
    my $ok = 0;
    for my $sector ($self->_tagged($line->{tag})) {
        $ok = 1 if $self->_spawn_door($sector, $dtype);
    }
    return $ok;
}

sub _donut {
    my ($self, $line) = @_;
    my $ok = 0;
    my $speed = int(FLOORSPEED / 2) || 1;
    for my $s1 ($self->_tagged($line->{tag})) {
        next if $s1->{specialdata} || !@{$s1->{lines} || []};
        my $edge = $s1->{lines}[0];
        my $s2 = ($edge->{frontsector} && $edge->{frontsector} == $s1)
            ? $edge->{backsector} : $edge->{frontsector};
        next if !$s2;
        my $s3;
        for my $ln (@{$s2->{lines} || []}) {
            next if !$ln->{backsector} || $ln->{backsector} == $s1;
            $s3 = $ln->{backsector};
            last;
        }
        next if !$s3;
        $ok = 1 if $self->_start_floor($s2, $s3->{floorheight}, 1, $speed, $s3->{floorpic});
        $ok = 1 if $self->_start_floor($s1, $s3->{floorheight}, -1, $speed);
    }
    return $ok;
}

sub _plat {
    my ($self, $line) = @_;
    my $ok = 0;
    for my $sector ($self->_tagged($line->{tag})) {
        next if $sector->{specialdata};
        my $low = _lowest_floor($sector);
        my $high = $sector->{floorheight};
        $low = $high - 8 * FRACUNIT if $low == $high;
        my $plat = {
            kind => 'plat', sector => $sector, status => PLAT_DOWN,
            speed => FRACUNIT, low => $low, high => $high,
            wait => 3 * TICRATE, count => 0, dead => 0,
        };
        $sector->{specialdata} = $plat;
        push @{$self->{thinkers}}, $plat;
        Doom::Sound::at($self->{world}, 'pstart');
        $ok = 1;
    }
    return $ok;
}

sub _tick_floor {
    my ($self, $move) = @_;
    my $res = move_plane(
        $self->{world}, $move->{sector}, $move->{speed}, $move->{dest},
        0, $move->{direction}
    );
    return if $res != RESULT_PASTDEST;
    $move->{sector}{floorpic} = $move->{pic} if defined $move->{pic};
    $move->{sector}{specialdata} = undef;
    $move->{dead} = 1;
    return;
}

sub _tick_plat {
    my ($self, $plat) = @_;
    if ($plat->{status} == PLAT_WAIT) {
        if (--$plat->{count} <= 0) {
            $plat->{status} = $plat->{sector}{floorheight} <= $plat->{low} ? PLAT_UP : PLAT_DOWN;
            Doom::Sound::at($self->{world}, 'pstart');
        }
        return;
    }
    my $up = $plat->{status} == PLAT_UP;
    my $res = move_plane(
        $self->{world}, $plat->{sector}, $plat->{speed},
        $up ? $plat->{high} : $plat->{low}, 0, $up ? 1 : -1
    );
    return if $res != RESULT_PASTDEST;
    if (!$up) {
        $plat->{status} = PLAT_WAIT;
        $plat->{count} = $plat->{wait};
        Doom::Sound::at($self->{world}, 'pstop');
    }
    else {
        $plat->{sector}{specialdata} = undef;
        $plat->{dead} = 1;
        Doom::Sound::at($self->{world}, 'pstop');
    }
    return;
}

sub move_plane {
    my ($world, $sector, $speed, $dest, $floor_or_ceiling, $direction, $crush) = @_;
    $crush ||= 0;
    my $last = $floor_or_ceiling == 0 ? $sector->{floorheight} : $sector->{ceilingheight};
    my ($next_h, $past);
    if ($direction == -1) {
        if ($last - $speed < $dest) {
            $next_h = $dest;
            $past = 1;
        }
        else {
            $next_h = $last - $speed;
            $past = 0;
        }
    }
    elsif ($last + $speed > $dest) {
        $next_h = $dest;
        $past = 1;
    }
    else {
        $next_h = $last + $speed;
        $past = 0;
    }
    if ($floor_or_ceiling == 0) {
        $sector->{floorheight} = $next_h;
    }
    else {
        $sector->{ceilingheight} = $next_h;
    }
    if (change_sector($world, $sector, $crush)) {
        if (!$crush || $past) {
            if ($floor_or_ceiling == 0) {
                $sector->{floorheight} = $last;
            }
            else {
                $sector->{ceilingheight} = $last;
            }
            change_sector($world, $sector, $crush);
        }
        return $past ? RESULT_PASTDEST : 1;
    }
    return $past ? RESULT_PASTDEST : 0;
}

sub surrounding_sectors {
    my ($sector) = @_;
    my (%seen, @out);
    for my $ln (@{$sector->{lines} || []}) {
        my $other = ($ln->{frontsector} && $ln->{frontsector} == $sector)
            ? $ln->{backsector} : $ln->{frontsector};
        next if !$other || $other == $sector;
        my $id = "$other";
        next if $seen{$id}++;
        push @out, $other;
    }
    return @out;
}

sub lowest_ceiling {
    my ($sector) = @_;
    my $h = 0x7FFFFFFF;
    for my $other (surrounding_sectors($sector)) {
        $h = $other->{ceilingheight} if $other->{ceilingheight} < $h;
    }
    return $h == 0x7FFFFFFF ? $sector->{ceilingheight} : $h;
}

1;
