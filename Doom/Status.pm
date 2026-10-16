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
# Barra de estado: vida, municao, armadura, rosto e chaves.
# Igual a doom/status.py.

package Doom::Status;

use strict;
use warnings;

use Doom::Collision ();
use Doom::Compat qw(as_u32);
use Doom::Defs qw(ANG45 ANG180);
use Doom::VVideo qw(draw_patch);

use constant AMMO_X => 44;
use constant AMMO_Y => 171;
use constant HEALTH_X => 90;
use constant HEALTH_Y => 171;
use constant ARMOR_X => 221;
use constant ARMOR_Y => 171;
use constant FACE_X => 143;
use constant FACE_Y => 168;
use constant ARMS_X => 111;
use constant ARMS_Y => 172;
use constant KEY_X => 239;

use constant ST_NUMPAINFACES => 5;
use constant ST_NUMSTRAIGHTFACES => 3;
use constant ST_FACESTRIDE => 8;
use constant ST_TURNOFFSET => 3;
use constant ST_OUCHOFFSET => 5;
use constant ST_EVILGRINOFFSET => 6;
use constant ST_RAMPAGEOFFSET => 7;
use constant ST_GODFACE => 40;
use constant ST_DEADFACE => 41;
use constant ST_EVILGRINCOUNT => 70;
use constant ST_STRAIGHTFACECOUNT => 17;
use constant ST_TURNCOUNT => 35;
use constant ST_RAMPAGEDELAY => 70;
use constant ST_MUCHPAIN => 20;

sub new {
    my ($class, $wad) = @_;
    my $self = bless { wad => $wad, rnd => 1, palette => 0 }, $class;
    $self->{playpal} = $wad->cache_lump_name('PLAYPAL');
    $self->{sbar} = $wad->cache_lump_name('STBAR');
    $self->{tall} = [map { $wad->cache_lump_name("STTNUM$_") } 0 .. 9];
    $self->{short} = [map { $wad->cache_lump_name("STYSNUM$_") } 0 .. 9];
    $self->{percent} = $wad->cache_lump_name('STTPRCNT');
    $self->{keys} = [map { _optional($wad, "STKEYS$_") } 0 .. 5];
    $self->{armsbg} = _optional($wad, 'STARMS');
    $self->{armsoff} = [map { $wad->cache_lump_name("STGNUM$_") } 2 .. 7];
    $self->{face0} = $wad->cache_lump_name('STFST00');
    $self->{faces} = [];
    for my $pain (0 .. ST_NUMPAINFACES - 1) {
        for my $look (0 .. ST_NUMSTRAIGHTFACES - 1) {
            push @{$self->{faces}}, _optional($wad, "STFST$pain$look");
        }
        push @{$self->{faces}}, _optional($wad, "STFTR${pain}0");
        push @{$self->{faces}}, _optional($wad, "STFTL${pain}0");
        push @{$self->{faces}}, _optional($wad, "STFOUCH$pain");
        push @{$self->{faces}}, _optional($wad, "STFEVL$pain");
        push @{$self->{faces}}, _optional($wad, "STFKILL$pain");
    }
    push @{$self->{faces}}, _optional($wad, 'STFGOD0');
    push @{$self->{faces}}, _optional($wad, 'STFDEAD0');
    $self->reset(undef);
    return $self;
}

sub reset {
    my ($self, $mo) = @_;
    $self->{faceindex} = 0;
    $self->{facecount} = 0;
    $self->{facepriority} = 0;
    $self->{oldhealth} = -1;
    $self->{painhealth} = -1;
    $self->{lastcalc} = 0;
    $self->{lastattack} = -1;
    $self->{oldweapons} = _weapons($mo);
    return;
}

sub decay {
    my ($mo) = @_;
    return if !$mo;
    $mo->{damagecount}-- if ($mo->{damagecount} || 0) > 0;
    $mo->{bonuscount}-- if ($mo->{bonuscount} || 0) > 0;
    return;
}

sub tick {
    my ($self, $mo) = @_;
    return if !$mo;
    $self->{rnd} = ($self->{rnd} * 1103515245 + 12345) & 0xFFFFFFFF;
    my $roll = ($self->{rnd} >> 16) & 255;
    _face($self, $mo, $roll);
    $self->{oldhealth} = $mo->{health} || 0;
    return;
}

sub draw {
    my ($self, $fb, $mo) = @_;
    return if !$mo;
    draw_patch($fb, 0, 168, $self->{sbar});
    draw_patch($fb, 104, 168, $self->{armsbg}) if $self->{armsbg};
    my $gun = $mo->{weapon} || '';
    my $ammo = ($gun eq 'shotgun' || $gun eq 'ssg') ? ($mo->{shells} || 0)
        : $gun eq 'rocket' ? ($mo->{rockets} || 0)
        : ($gun eq 'plasma' || $gun eq 'bfg') ? ($mo->{cells} || 0)
        : ($gun eq 'fist' || $gun eq 'chainsaw') ? 0
        : ($mo->{ammo} || 0);
    _number($fb, AMMO_X, AMMO_Y, $ammo, $self->{tall});
    _number($fb, HEALTH_X, HEALTH_Y, $mo->{health} || 0, $self->{tall});
    draw_patch($fb, HEALTH_X, HEALTH_Y, $self->{percent});
    _number($fb, ARMOR_X, ARMOR_Y, $mo->{armorpoints} || 0, $self->{tall});
    draw_patch($fb, ARMOR_X, ARMOR_Y, $self->{percent});

    my @owned = (
        ($mo->{owns_shotgun} || $mo->{owns_ssg}) ? 1 : 0,
        $mo->{owns_chaingun} ? 1 : 0,
        $mo->{owns_rocket} ? 1 : 0,
        $mo->{owns_plasma} ? 1 : 0,
        $mo->{owns_bfg} ? 1 : 0,
        0,
    );
    for my $i (0 .. 5) {
        my $x = ARMS_X + ($i % 3) * 12;
        my $y = ARMS_Y + int($i / 3) * 10;
        if ($owned[$i]) {
            draw_patch($fb, $x, $y, $self->{short}[$i + 2]);
        }
        else {
            draw_patch($fb, $x, $y, $self->{armsoff}[$i]);
        }
    }

    my $face = $self->{faces}[$self->{faceindex} || 0] || $self->{face0};
    draw_patch($fb, FACE_X, FACE_Y, $face);

    my $cards = $mo->{cards} || [];
    my @slots = ([0, 3], [1, 4], [2, 5]);
    for my $slot (0 .. 2) {
        my ($card, $skull) = @{$slots[$slot]};
        next if !$cards->[$card] && !$cards->[$skull];
        my $index = $cards->[$skull] ? $skull : $card;
        draw_patch($fb, KEY_X, 171 + $slot * 10, $self->{keys}[$index]) if $self->{keys}[$index];
    }

    my @have = ($mo->{ammo} || 0, $mo->{shells} || 0, $mo->{cells} || 0, $mo->{rockets} || 0);
    my @max = ($mo->{maxammo} || 200, $mo->{maxshells} || 50, $mo->{maxcells} || 300, $mo->{maxrockets} || 50);
    my @at = ([288, 173], [288, 179], [288, 191], [288, 185]);
    my @mx = ([314, 173], [314, 179], [314, 191], [314, 185]);
    for my $i (0 .. 3) {
        _number($fb, $at[$i][0], $at[$i][1], $have[$i], $self->{short});
        _number($fb, $mx[$i][0], $mx[$i][1], $max[$i], $self->{short});
    }
    return;
}

sub apply_palette {
    my ($self, $video, $mo) = @_;
    my $palette = 0;
    if ($mo) {
        my $cnt = $mo->{damagecount} || 0;
        if ($cnt) {
            my $n = ($cnt + 7) >> 3;
            $n = 7 if $n > 7;
            $palette = $n + 1;
        }
        elsif ($mo->{bonuscount}) {
            my $n = (($mo->{bonuscount} || 0) + 7) >> 3;
            $n = 3 if $n > 3;
            $palette = $n + 9;
        }
    }
    return if $palette == ($self->{palette} || 0);
    $self->{palette} = $palette;
    my $raw = substr($self->{playpal} || '', $palette * 768, 768);
    $video->set_palette($raw) if length($raw) == 768;
    return;
}

sub _optional {
    my ($wad, $name) = @_;
    my $n = $wad->check_num_for_name($name);
    return if !defined $n || $n < 0;
    return $wad->cache_lump_num($n);
}

sub _weapons {
    my ($mo) = @_;
    my @w = (0) x 9;
    $w[1] = 1;
    $w[2] = 1 if $mo && ($mo->{owns_shotgun} || $mo->{owns_ssg});
    $w[7] = 1 if $mo && $mo->{owns_chainsaw};
    $w[3] = 1 if $mo && $mo->{owns_chaingun};
    $w[4] = 1 if $mo && $mo->{owns_rocket};
    $w[5] = 1 if $mo && $mo->{owns_plasma};
    $w[6] = 1 if $mo && $mo->{owns_bfg};
    return \@w;
}

sub _pain_offset {
    my ($self, $mo) = @_;
    my $health = $mo->{health} || 0;
    $health = 0 if $health < 0;
    $health = 100 if $health > 100;
    if ($health != $self->{painhealth}) {
        $self->{lastcalc} = ST_FACESTRIDE * int((100 - $health) * ST_NUMPAINFACES / 101);
        $self->{painhealth} = $health;
    }
    return $self->{lastcalc};
}

sub _face {
    my ($self, $mo, $roll) = @_;
    my $health = $mo->{health} || 0;
    if ($self->{facepriority} < 10 && $health <= 0) {
        $self->{facepriority} = 9;
        $self->{faceindex} = ST_DEADFACE;
        $self->{facecount} = 1;
    }
    my $owned = _weapons($mo);
    if ($self->{facepriority} < 9 && ($mo->{bonuscount} || 0) > 0) {
        my $grin = 0;
        for my $i (0 .. 8) {
            my $now = $owned->[$i] ? 1 : 0;
            my $was = $self->{oldweapons}[$i] ? 1 : 0;
            if ($now != $was) {
                $grin = 1;
                $self->{oldweapons}[$i] = $now;
            }
        }
        if ($grin) {
            $self->{facepriority} = 8;
            $self->{facecount} = ST_EVILGRINCOUNT;
            $self->{faceindex} = _pain_offset($self, $mo) + ST_EVILGRINOFFSET;
        }
    }
    my $attacker = $mo->{attacker};
    if ($self->{facepriority} < 8 && ($mo->{damagecount} || 0) > 0
        && $attacker && $attacker != $mo)
    {
        $self->{facepriority} = 7;
        if ($health - $self->{oldhealth} > ST_MUCHPAIN) {
            $self->{facecount} = ST_TURNCOUNT;
            $self->{faceindex} = _pain_offset($self, $mo) + ST_OUCHOFFSET;
        }
        else {
            my $bad = Doom::Collision::angle_to($mo->{x}, $mo->{y}, $attacker->{x}, $attacker->{y});
            my ($diff, $right);
            if (as_u32($bad) > as_u32($mo->{angle})) {
                $diff = as_u32($bad - $mo->{angle});
                $right = $diff > as_u32(ANG180);
            }
            else {
                $diff = as_u32($mo->{angle} - $bad);
                $right = $diff <= as_u32(ANG180);
            }
            $self->{facecount} = ST_TURNCOUNT;
            $self->{faceindex} = _pain_offset($self, $mo);
            if ($diff < as_u32(ANG45)) {
                $self->{faceindex} += ST_RAMPAGEOFFSET;
            }
            elsif ($right) {
                $self->{faceindex} += ST_TURNOFFSET;
            }
            else {
                $self->{faceindex} += ST_TURNOFFSET + 1;
            }
        }
    }
    if ($self->{facepriority} < 7 && ($mo->{damagecount} || 0) > 0) {
        if ($health - $self->{oldhealth} > ST_MUCHPAIN) {
            $self->{facepriority} = 7;
            $self->{facecount} = ST_TURNCOUNT;
            $self->{faceindex} = _pain_offset($self, $mo) + ST_OUCHOFFSET;
        }
        else {
            $self->{facepriority} = 6;
            $self->{facecount} = ST_TURNCOUNT;
            $self->{faceindex} = _pain_offset($self, $mo) + ST_RAMPAGEOFFSET;
        }
    }
    if ($self->{facepriority} < 6) {
        if ($mo->{attackdown}) {
            if ($self->{lastattack} == -1) {
                $self->{lastattack} = ST_RAMPAGEDELAY;
            }
            else {
                $self->{lastattack}--;
                if ($self->{lastattack} == 0) {
                    $self->{facepriority} = 5;
                    $self->{faceindex} = _pain_offset($self, $mo) + ST_RAMPAGEOFFSET;
                    $self->{facecount} = 1;
                    $self->{lastattack} = 1;
                }
            }
        }
        else {
            $self->{lastattack} = -1;
        }
    }
    if ($health > 0 && $self->{facepriority} < 5
        && ((($mo->{cheats} || 0) & 1) || ($mo->{pow_invul} || 0) > 0))
    {
        $self->{facepriority} = 4;
        $self->{faceindex} = ST_GODFACE;
        $self->{facecount} = 1;
        return;
    }
    if ($self->{facecount} == 0) {
        $self->{faceindex} = _pain_offset($self, $mo) + ($roll % 3);
        $self->{facecount} = ST_STRAIGHTFACECOUNT;
        $self->{facepriority} = 0;
    }
    $self->{facecount}--;
    return;
}

sub draw_text {
    my ($self, $fb, $x, $y, $text) = @_;
    my $font = $self->{font} ||= _font($self->{wad});
    for my $ch (split //, uc $text) {
        if ($ch eq ' ') {
            $x += 4;
            next;
        }
        my $n = ord($ch);
        my $patch = ($n >= 33 && $n <= 126) ? $font->[$n] : undef;
        if (!$patch) {
            $x += 4;
            next;
        }
        draw_patch($fb, $x, $y, $patch);
        my ($w) = unpack('s<', $patch);
        $x += ($w || 0) > 4 ? $w : 4;
    }
    return;
}

sub _font {
    my ($wad) = @_;
    my @font;
    for my $n (33 .. 126) {
        $font[$n] = _optional($wad, sprintf('STCFN%03d', $n));
    }
    return \@font;
}

sub _number {
    my ($fb, $x, $y, $value, $font) = @_;
    my $width = unpack('s<', $font->[0]);
    $x -= $width;
    $value = abs($value || 0);
    for (1 .. 3) {
        draw_patch($fb, $x, $y, $font->[$value % 10]);
        $x -= $width;
        $value = int($value / 10);
        last if $value == 0;
    }
    return;
}

1;
