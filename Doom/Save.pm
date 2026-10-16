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
# Seis vagas de jogo. Igual a doom/saveg.py no cabecalho e no estado.

package Doom::Save;

use strict;
use warnings;

use JSON::PP ();
use File::Spec ();

use Doom::Collision ();

use constant SAVESTRINGSIZE => 24;
use constant SAVE_MAGIC => 'DOOMPL01';
use constant SLOTS => 6;
use constant EMPTY => 'empty slot';

my @MOBJ_KEYS = qw(
    x y z angle momx momy momz radius height floorz ceilingz
    flags health type doomednum sprite frame istate tics alive
    reactiontime movedir movecount threshold lastlook
    ammo maxammo shells maxshells rockets maxrockets cells maxcells weapon
    owns_shotgun owns_chaingun owns_rocket owns_plasma owns_bfg owns_ssg owns_chainsaw
    cheats pow_invul pow_berserk pow_invis pow_suit pow_map pow_lite
    armorpoints armortype gunstate gunsprite gunframe guntics gunstep
    refire attackdown flash_tics gunflash gunflashframe extralight
    kills items secrets damagecount bonuscount wantgun
);
my @THINKER_KEYS = qw(
    type direction topheight speed topwait topcountdown
    dest status low high wait count pic
    crush ctype bottomheight perpetual
);

sub new {
    my ($class, $dir) = @_;
    return bless { dir => $dir || '.' }, $class;
}

sub slots { return SLOTS }
sub empty { return EMPTY }

sub path {
    my ($self, $slot) = @_;
    return File::Spec->catfile($self->{dir}, sprintf('doomsav%d.dsg', $slot));
}

sub description {
    my ($self, $slot) = @_;
    my $data = _read_file($self->path($slot));
    return (EMPTY, 0) if !defined $data;
    return (EMPTY, 0) if length($data) < SAVESTRINGSIZE + length(SAVE_MAGIC);
    return (EMPTY, 0) if substr($data, SAVESTRINGSIZE, length(SAVE_MAGIC)) ne SAVE_MAGIC;
    my $desc = substr($data, 0, SAVESTRINGSIZE);
    $desc =~ s/\x00.*//s;
    $desc =~ s/\s+\z//;
    return ($desc || EMPTY, 1);
}

sub write_save {
    my ($self, $slot, $desc, $state) = @_;
    return 0 if !$state || $slot < 0 || $slot >= SLOTS;
    my $json = JSON::PP->new->ascii->canonical->encode($state);
    my $raw = substr($desc || '', 0, SAVESTRINGSIZE - 1);
    $raw .= "\x00" x (SAVESTRINGSIZE - length($raw));
    my $path = $self->path($slot);
    my $tmp = $path . '.tmp';
    my $ok = eval {
        open my $fh, '>:raw', $tmp or die $!;
        print {$fh} $raw, SAVE_MAGIC, $json or die $!;
        close $fh or die $!;
        unlink $path;
        rename $tmp, $path or die $!;
        1;
    };
    unlink $tmp if !$ok && -f $tmp;
    return $ok ? 1 : 0;
}

sub read_save {
    my ($self, $slot) = @_;
    my $data = _read_file($self->path($slot));
    return if !defined $data;
    my $need = SAVESTRINGSIZE + length(SAVE_MAGIC);
    return if length($data) < $need;
    return if substr($data, SAVESTRINGSIZE, length(SAVE_MAGIC)) ne SAVE_MAGIC;
    my $state = eval { JSON::PP->new->decode(substr($data, $need)) };
    return if !$state || ref $state ne 'HASH';
    return $state;
}

sub capture {
    my ($world, $specials, $episode, $mapn, $skill) = @_;
    my $mobjs = $world->{mobjs} || [];
    my %at;
    for my $i (0 .. $#$mobjs) {
        $at{$mobjs->[$i]} = $i if $mobjs->[$i];
    }
    my @things;
    for my $mo (@$mobjs) {
        next if !$mo;
        my %rec;
        for my $key (@MOBJ_KEYS) {
            $rec{$key} = $mo->{$key} if defined $mo->{$key};
        }
        $rec{player} = $mo->{player} ? 1 : 0;
        $rec{cards} = [@{$mo->{cards}}] if $mo->{cards};
        $rec{target} = $at{$mo->{target}} if $mo->{target} && exists $at{$mo->{target}};
        push @things, \%rec;
    }
    my @thinkers;
    for my $th (@{$specials->{thinkers} || []}) {
        next if !$th || $th->{dead} || !$th->{sector};
        my %rec = (kind => $th->{kind} || 'door', sector => $th->{sector}{i_sector});
        for my $key (@THINKER_KEYS) {
            $rec{$key} = $th->{$key} if defined $th->{$key};
        }
        push @thinkers, \%rec;
    }
    my @buttons;
    for my $btn (@{$specials->{buttons} || []}) {
        next if !$btn->{line};
        push @buttons, {
            line => $btn->{line}{i_line},
            where => $btn->{where},
            texture => $btn->{texture},
            timer => $btn->{timer},
        };
    }
    return {
        episode => $episode,
        mapn => $mapn,
        skill => $skill,
        time => $specials->{time} || 0,
        totalkills => $world->{totalkills} || 0,
        totalitems => $world->{totalitems} || 0,
        totalsecret => $world->{totalsecret} || 0,
        sectors => [
            map { {
                floorheight => $_->{floorheight},
                ceilingheight => $_->{ceilingheight},
                floorpic => $_->{floorpic},
                ceilingpic => $_->{ceilingpic},
                lightlevel => $_->{lightlevel},
                special => $_->{special} || 0,
            } } @{$world->{sectors} || []}
        ],
        sides => [
            map { {
                textureoffset => $_->{textureoffset},
                rowoffset => $_->{rowoffset},
                toptexture => $_->{toptexture},
                bottomtexture => $_->{bottomtexture},
                midtexture => $_->{midtexture},
            } } @{$world->{sides} || []}
        ],
        lines => [
            map { { flags => $_->{flags} || 0, special => $_->{special} || 0 } }
                @{$world->{lines} || []}
        ],
        mobjs => \@things,
        thinkers => \@thinkers,
        buttons => \@buttons,
    };
}

sub restore {
    my ($world, $specials, $mo, $data) = @_;
    return 0 if !$data || !$mo;
    my $sectors = $world->{sectors} || [];
    my $saved_sectors = $data->{sectors} || [];
    for my $i (0 .. $#$saved_sectors) {
        last if $i > $#$sectors;
        my $sec = $sectors->[$i];
        my $rec = $saved_sectors->[$i];
        for my $key (qw(floorheight ceilingheight floorpic ceilingpic lightlevel special)) {
            $sec->{$key} = $rec->{$key} if defined $rec->{$key};
        }
        $sec->{specialdata} = undef;
    }
    my $sides = $world->{sides} || [];
    my $saved_sides = $data->{sides} || [];
    for my $i (0 .. $#$saved_sides) {
        last if $i > $#$sides;
        my $side = $sides->[$i];
        my $rec = $saved_sides->[$i];
        for my $key (qw(textureoffset rowoffset toptexture bottomtexture midtexture)) {
            $side->{$key} = $rec->{$key} if defined $rec->{$key};
        }
    }
    my $lines = $world->{lines} || [];
    my $saved_lines = $data->{lines} || [];
    for my $i (0 .. $#$saved_lines) {
        last if $i > $#$lines;
        $lines->[$i]{flags} = $saved_lines->[$i]{flags} || 0;
        $lines->[$i]{special} = $saved_lines->[$i]{special} || 0;
    }
    for my $th (@{$world->{mobjs} || []}) {
        Doom::Collision::unset_thing_position($world, $th);
    }
    my @made;
    my $seen_player = 0;
    for my $rec (@{$data->{mobjs} || []}) {
        my $body;
        if ($rec->{player} && !$seen_player) {
            $body = $mo;
            $seen_player = 1;
        }
        else {
            $body = {};
        }
        _fill_mobj($body, $rec);
        push @made, $body;
    }
    return 0 if !$seen_player;
    for my $i (0 .. $#made) {
        my $ti = $data->{mobjs}[$i]{target};
        $made[$i]{target} = (defined $ti && $made[$ti]) ? $made[$ti] : undef;
        $made[$i]{bnext} = undef;
        $made[$i]{bprev} = undef;
        $made[$i]{blocklinked} = 0;
        Doom::Collision::set_thing_position($world, $made[$i]);
    }
    $world->{mobjs} = \@made;
    $world->{totalkills} = $data->{totalkills} if defined $data->{totalkills};
    $world->{totalitems} = $data->{totalitems} if defined $data->{totalitems};
    $world->{totalsecret} = $data->{totalsecret} if defined $data->{totalsecret};
    $specials->{thinkers} = [];
    for my $rec (@{$data->{thinkers} || []}) {
        my $sec = $sectors->[$rec->{sector} || 0];
        next if !$sec;
        my %th = (kind => $rec->{kind} || 'door', sector => $sec, dead => 0);
        for my $key (@THINKER_KEYS) {
            $th{$key} = $rec->{$key} if defined $rec->{$key};
        }
        my $box = \%th;
        $sec->{specialdata} = $box;
        push @{$specials->{thinkers}}, $box;
    }
    $specials->{buttons} = [];
    for my $rec (@{$data->{buttons} || []}) {
        my $ln = $lines->[$rec->{line} || 0];
        next if !$ln;
        push @{$specials->{buttons}}, {
            line => $ln,
            where => $rec->{where},
            texture => $rec->{texture},
            timer => $rec->{timer},
        };
    }
    $specials->{time} = $data->{time} || 0;
    $specials->{exit} = 0;
    $specials->{said} = 0;
    return 1;
}

sub _fill_mobj {
    my ($body, $rec) = @_;
    for my $key (@MOBJ_KEYS) {
        $body->{$key} = $rec->{$key} if defined $rec->{$key};
    }
    $body->{player} = $rec->{player} ? 1 : undef;
    $body->{cards} = [@{$rec->{cards}}] if $rec->{cards};
    $body->{alive} = $rec->{alive} ? 1 : 0;
    $body->{attacker} = undef;
    return;
}

sub _read_file {
    my ($path) = @_;
    return if !-f $path;
    open my $fh, '<:raw', $path or return;
    local $/;
    my $data = <$fh>;
    close $fh;
    return $data;
}

1;
