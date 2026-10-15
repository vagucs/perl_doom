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
# A porta manual sobe e desce. Igual a doom/specials.py.

package Doom::Specials;

use strict;
use warnings;

use Doom::Collision qw(change_sector);
use Doom::Defs qw(FRACUNIT);

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
use constant RESULT_PASTDEST => 2;
use constant IT_BLUECARD   => 0;
use constant IT_YELLOWCARD => 1;
use constant IT_REDCARD    => 2;
use constant IT_BLUESKULL  => 3;
use constant IT_YELLOWSKULL => 4;
use constant IT_REDSKULL   => 5;

sub new {
    my ($class, $world) = @_;
    return bless { world => $world, thinkers => [] }, $class;
}

sub tick {
    my ($self) = @_;
    my @alive;
    for my $door (@{$self->{thinkers}}) {
        $self->_tick_door($door);
        push @alive, $door if !$door->{dead};
    }
    $self->{thinkers} = \@alive;
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
    return 0;
}

sub vertical_door {
    my ($self, $line, $thing) = @_;
    my $spec = $line->{special};
    if ($thing->{player}) {
        if (($spec == 26 || $spec == 32) && !_has_key($thing, IT_BLUECARD, IT_BLUESKULL)) {
            print "falta a chave azul\n";
            return;
        }
        if (($spec == 27 || $spec == 34) && !_has_key($thing, IT_YELLOWCARD, IT_YELLOWSKULL)) {
            print "falta a chave amarela\n";
            return;
        }
        if (($spec == 28 || $spec == 33) && !_has_key($thing, IT_REDCARD, IT_REDSKULL)) {
            print "falta a chave vermelha\n";
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

sub _spawn_door {
    my ($self, $sector, $dtype) = @_;
    if ($sector->{specialdata}) {
        my $door = $sector->{specialdata};
        if ($door->{kind} && $door->{kind} eq 'door'
            && ($dtype == VLD_NORMAL || $dtype == VLD_BLAZERAISE))
        {
            $door->{direction} = $door->{direction} == -1 ? 1 : -1;
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
    return 1;
}

sub _tick_door {
    my ($self, $door) = @_;
    if ($door->{direction} == 0) {
        $door->{topcountdown}--;
        return if $door->{topcountdown} > 0;
        if ($door->{type} == VLD_NORMAL || $door->{type} == VLD_BLAZERAISE || $door->{type} == VLD_CLOSE) {
            $door->{direction} = -1;
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
