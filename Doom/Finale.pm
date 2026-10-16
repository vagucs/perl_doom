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
# Texto de fim de episodio. Igual a doom/finale.py na historia.
# No episodio 3 o coelho atravessa a tela.
# No Doom 2 o desfile de monstros fecha o jogo.

package Doom::Finale;

use strict;
use warnings;

use Doom::Info qw(sprite_name);
use Doom::VVideo qw(fill draw_patch);

use constant TEXTSPEED => 3;
use constant TEXTWAIT => 250;

my $E1TEXT = "Once you beat the big badasses and\n"
    . "clean out the moon base you're supposed\n"
    . "to win, aren't you? Aren't you? Where's\n"
    . "your fat reward and ticket home? What\n"
    . "the hell is this? It's not supposed to\n"
    . "end this way!\n"
    . "\n"
    . "It stinks like rotten meat, but looks\n"
    . "like the lost Deimos base.  Looks like\n"
    . "you're stuck on The Shores of Hell.\n"
    . "The only way out is through.\n"
    . "\n"
    . "To continue the DOOM experience, play\n"
    . "The Shores of Hell and its amazing\n"
    . "sequel, Inferno!\n";

my $E2TEXT = "You've done it! The hideous cyber-\n"
    . "demon lord that ruled the lost Deimos\n"
    . "moon base has been slain and you\n"
    . "are triumphant! But ... where are\n"
    . "you? You clamber to the edge of the\n"
    . "moon and look down to see the awful\n"
    . "truth.\n"
    . "\n"
    . "Deimos floats above Hell itself!\n"
    . "You've never heard of anyone escaping\n"
    . "from Hell, but you'll make the bastards\n"
    . "sorry they ever heard of you! Quickly,\n"
    . "you rappel down to  the surface of\n"
    . "Hell.\n"
    . "\n"
    . "Now, it's on to the final chapter of\n"
    . "DOOM! -- Inferno.\n";

my $E3TEXT = "The loathsome spiderdemon that\n"
    . "masterminded the invasion of the moon\n"
    . "bases and caused so much death has had\n"
    . "its ass kicked for all time.\n"
    . "\n"
    . "A hidden doorway opens and you enter.\n"
    . "You've proven too tough for Hell to\n"
    . "contain, and now Hell at last plays\n"
    . "fair -- for you emerge from the door\n"
    . "to see the green fields of Earth!\n"
    . "Home at last.\n"
    . "\n"
    . "You wonder what's been happening on\n"
    . "Earth while you were battling evil\n"
    . "unleashed. It's good that no Hell-\n"
    . "spawn could have come through that\n"
    . "door with you ...\n";

my $E4TEXT = "the spider mastermind must have sent forth\n"
    . "its legions of hellspawn before your\n"
    . "final confrontation with that terrible\n"
    . "beast from hell.  but you stepped forward\n"
    . "and brought forth eternal damnation and\n"
    . "suffering upon the horde as a true hero\n"
    . "would in the face of something so evil.\n"
    . "\n"
    . "besides, someone was gonna pay for what\n"
    . "happened to daisy, your pet rabbit.\n"
    . "\n"
    . "but now, you see spread before you more\n"
    . "potential pain and gibbitude as a nation\n"
    . "of demons run amok among our cities.\n"
    . "\n"
    . "next stop, hell on earth!";

my $C1TEXT = "YOU HAVE ENTERED DEEPLY INTO THE INFESTED\nSTARPORT. BUT SOMETHING IS WRONG. THE\nMONSTERS HAVE BROUGHT THEIR OWN REALITY\nWITH THEM, AND THE STARPORT'S TECHNOLOGY\nIS BEING SUBVERTED BY THEIR PRESENCE.\n\nAHEAD, YOU SEE AN OUTPOST OF HELL, A\nFORTIFIED ZONE. IF YOU CAN GET PAST IT,\nYOU CAN PENETRATE INTO THE HAUNTED HEART\nOF THE STARBASE AND FIND THE CONTROLLING\nSWITCH WHICH HOLDS EARTH'S POPULATION\nHOSTAGE.";
my $C2TEXT = "YOU HAVE WON! YOUR VICTORY HAS ENABLED\nHUMANKIND TO EVACUATE EARTH AND ESCAPE\nTHE NIGHTMARE.  NOW YOU ARE THE ONLY\nHUMAN LEFT ON THE FACE OF THE PLANET.\nCANNIBAL MUTATIONS, CARNIVOROUS ALIENS,\nAND EVIL SPIRITS ARE YOUR ONLY NEIGHBORS.\nYOU SIT BACK AND WAIT FOR DEATH, CONTENT\nTHAT YOU HAVE SAVED YOUR SPECIES.\n\nBUT THEN, EARTH CONTROL BEAMS DOWN A\nMESSAGE FROM SPACE: \"SENSORS HAVE LOCATED\nTHE SOURCE OF THE ALIEN INVASION. IF YOU\nGO THERE, YOU MAY BE ABLE TO BLOCK THEIR\nENTRY.  THE ALIEN BASE IS IN THE HEART OF\nYOUR OWN HOME CITY, NOT FAR FROM THE\nSTARPORT.\" SLOWLY AND PAINFULLY YOU GET\nUP AND RETURN TO THE FRAY.";
my $C3TEXT = "YOU ARE AT THE CORRUPT HEART OF THE CITY,\nSURROUNDED BY THE CORPSES OF YOUR ENEMIES.\nYOU SEE NO WAY TO DESTROY THE CREATURES'\nENTRYWAY ON THIS SIDE, SO YOU CLENCH YOUR\nTEETH AND PLUNGE THROUGH IT.\n\nTHERE MUST BE A WAY TO CLOSE IT ON THE\nOTHER SIDE. WHAT DO YOU CARE IF YOU'VE\nGOT TO GO THROUGH HELL TO GET TO IT?";
my $C4TEXT = "THE HORRENDOUS VISAGE OF THE BIGGEST\nDEMON YOU'VE EVER SEEN CRUMBLES BEFORE\nYOU, AFTER YOU PUMP YOUR ROCKETS INTO\nHIS EXPOSED BRAIN. THE MONSTER SHRIVELS\nUP AND DIES, ITS THRASHING LIMBS\nDEVASTATING UNTOLD MILES OF HELL'S\nSURFACE.\n\nYOU'VE DONE IT. THE INVASION IS OVER.\nEARTH IS SAVED. HELL IS A WRECK. YOU\nWONDER WHERE BAD FOLKS WILL GO WHEN THEY\nDIE, NOW. WIPING THE SWEAT FROM YOUR\nFOREHEAD YOU BEGIN THE LONG TREK BACK\nHOME. REBUILDING EARTH OUGHT TO BE A\nLOT MORE FUN THAN RUINING IT WAS.\n";
my $C5TEXT = "CONGRATULATIONS, YOU'VE FOUND THE SECRET\nLEVEL! LOOKS LIKE IT'S BEEN BUILT BY\nHUMANS, RATHER THAN DEMONS. YOU WONDER\nWHO THE INMATES OF THIS CORNER OF HELL\nWILL BE.";
my $C6TEXT = "CONGRATULATIONS, YOU'VE FOUND THE\nSUPER SECRET LEVEL!  YOU'D BETTER\nBLAZE THROUGH THIS ONE!\n";

my @CAST = (
    ['ZOMBIEMAN', 1],
    ['SHOTGUN GUY', 2],
    ['HEAVY WEAPON DUDE', 10],
    ['IMP', 11],
    ['DEMON', 12],
    ['LOST SOUL', 18],
    ['CACODEMON', 14],
    ['HELL KNIGHT', 17],
    ['BARON OF HELL', 15],
    ['ARACHNOTRON', 20],
    ['PAIN ELEMENTAL', 22],
    ['REVENANT', 5],
    ['MANCUBUS', 8],
    ['ARCH-VILE', 3],
    ['THE SPIDER MASTERMIND', 19],
    ['THE CYBERDEMON', 21],
    ['OUR HERO', 0],
);

my %CAST_SFX = (
    154 => 'shtgn', 185 => 'pistol', 218 => 'shotgn', 256 => 'vilatk',
    336 => 'skeswg', 338 => 'skepch', 340 => 'skeatk',
    383 => 'firsht', 380 => 'firsht', 377 => 'firsht',
    417 => 'shotgn', 418 => 'shotgn', 419 => 'shotgn',
    454 => 'claw', 486 => 'sgtatk', 538 => 'firsht', 567 => 'firsht',
    505 => 'firsht', 590 => 'sklatk', 616 => 'shotgn', 617 => 'shotgn',
    648 => 'plasma', 685 => 'rlaunc', 687 => 'rlaunc', 689 => 'rlaunc',
    710 => 'sklatk',
);

use constant MI_SEE => 3;
use constant MI_MELEE => 10;
use constant MI_MISSILE => 11;
use constant MI_DEATH => 12;
use constant S_NULL => 0;
use constant S_PLAY_ATK1 => 154;
use constant STAGE_CAST => 2;

sub _lump {
    my ($wad, $name) = @_;
    my $n = $wad->check_num_for_name($name);
    return undef if !defined $n || $n < 0;
    return $wad->cache_lump_name($name);
}

sub _tile {
    my ($flat) = @_;
    return "\0" x (320 * 200) if !defined $flat || length($flat) < 4096;
    my $fb = '';
    for my $y (0 .. 199) {
        $fb .= substr($flat, ($y & 63) * 64, 64) x 5;
    }
    return $fb;
}

sub new {
    my ($class, $wad, $sound, $episode, $mapn, $res) = @_;
    my $commercial = $wad->check_num_for_name('MAP01') >= 0;
    my %text = (1 => $E1TEXT, 2 => $E2TEXT, 3 => $E3TEXT, 4 => $E4TEXT);
    my %flat = (1 => 'FLOOR4_8', 2 => 'SFLR6_1', 3 => 'MFLR8_4', 4 => 'MFLR8_3');
    my ($body, $floor) = ($text{$episode} // $E1TEXT, $flat{$episode} // 'FLOOR4_8');
    if ($commercial) {
        ($floor, $body) = _screen($wad, $mapn || 1);
    }
    my $self = bless {
        text => $body,
        stage => 0, count => 0, done => 0, action => '', need_wipe => 0,
        commercial => $commercial ? 1 : 0, mapn => $mapn || 0,
        wad => $wad, res => $res, sound => $sound, nextmap => 0,
    }, $class;
    $self->{tiled} = _tile(_lump($wad, $floor));
    my @font;
    for my $code (33 .. 95) {
        $font[$code] = _lump($wad, sprintf('STCFN%03d', $code));
    }
    $self->{font} = \@font;
    $self->{bossback} = _lump($wad, 'BOSSBACK');
    my $pfub1 = _lump($wad, 'PFUB1');
    my $pfub2 = _lump($wad, 'PFUB2');
    if (!$commercial && $episode == 3 && $pfub1 && $pfub2) {
        $self->{bunny} = 1;
        $self->{wide} = _wide($pfub2, $pfub1);
        $self->{last_stage} = -1;
        $self->{ends} = [map { _lump($wad, "END$_") } 0 .. 6];
    }
    elsif (!$commercial) {
        my $name = $episode == 2 ? 'VICTORY2' : $episode == 4 ? 'ENDPIC'
            : ($wad->check_num_for_name('CREDIT') >= 0 ? 'CREDIT' : 'HELP2');
        $self->{art} = _lump($wad, $name) // _lump($wad, 'HELP1');
    }
    if ($sound) {
        $sound->change_music($commercial ? 'read_m' : 'victor', 1);
    }
    return $self;
}

sub commercial_map {
    my ($wad, $map, $secret) = @_;
    return 0 if !$wad || $wad->check_num_for_name('MAP01') < 0;
    return 1 if $map == 6 || $map == 11 || $map == 20 || $map == 30;
    return $secret && ($map == 15 || $map == 31) ? 1 : 0;
}

sub _screen {
    my ($wad, $map) = @_;
    my %doom2 = (
        6 => ['SLIME16', $C1TEXT], 11 => ['RROCK14', $C2TEXT],
        20 => ['RROCK07', $C3TEXT], 30 => ['RROCK17', $C4TEXT],
        15 => ['RROCK13', $C5TEXT], 31 => ['RROCK19', $C6TEXT],
    );
    my $row = $doom2{$map} || ['SLIME16', $C1TEXT];
    return @$row;
}

sub _stamp {
    my ($dest, $stride, $x0, $patch) = @_;
    return if !defined $patch || length($patch) < 8;
    my $width = unpack('s<', $patch);
    for my $col (0 .. $width - 1) {
        my $x = $x0 + $col;
        next if $x < 0 || $x >= $stride;
        my $column = unpack('V', substr($patch, 8 + $col * 4, 4));
        while ($column + 1 < length($patch)) {
            my $top = ord(substr($patch, $column, 1));
            last if $top == 255;
            my $length = ord(substr($patch, $column + 1, 1));
            my $source = $column + 3;
            for my $i (0 .. $length - 1) {
                last if $top + $i >= 200 || $source + $i >= length($patch);
                substr($$dest, ($top + $i) * $stride + $x, 1) = substr($patch, $source + $i, 1);
            }
            $column += $length + 4;
        }
    }
    return;
}

sub _wide {
    my ($left, $right) = @_;
    my $pic = "\0" x (640 * 200);
    _stamp(\$pic, 640, 0, $left);
    _stamp(\$pic, 640, 320, $right);
    return $pic;
}

sub _scroll {
    my ($count) = @_;
    my $scroll = 320 - int(($count - 230) / 2);
    $scroll = 320 if $scroll > 320;
    $scroll = 0 if $scroll < 0;
    return $scroll;
}

sub _draw_bunny {
    my ($self, $fb) = @_;
    my $count = $self->{count};
    my $scroll = _scroll($count);
    my $wide = $self->{wide};
    my $pic = '';
    for my $y (0 .. 199) {
        $pic .= substr($wide, $y * 640 + $scroll, 320);
    }
    $$fb = $pic;
    return if $count < 1130;
    my $stage = $count < 1180 ? 0 : int(($count - 1180) / 5);
    $stage = 6 if $stage > 6;
    if ($stage > $self->{last_stage}) {
        $self->{sound}->play('pistol') if $self->{sound};
        $self->{last_stage} = $stage;
    }
    my $end = $self->{ends}[$stage];
    draw_patch($fb, int((320 - 104) / 2), int((200 - 64) / 2), $end) if $end;
    return;
}

sub tick {
    my ($self, $skip) = @_;
    return if $self->{done};
    my $started = 0;
    if ($self->{commercial} && $self->{stage} == 0 && $self->{count} > 50 && $skip) {
        if ($self->{mapn} == 30) {
            _start_cast($self);
            $started = 1;
        }
        else {
            $self->{action} = 'worlddone';
            $self->{done} = 1;
            return;
        }
    }
    $self->{count}++;
    if ($self->{stage} == STAGE_CAST) {
        _cast_hit($self) if $skip && !$started && !$self->{castdeath};
        _cast_tick($self);
        return;
    }
    return if $self->{commercial};
    if ($self->{stage} == 0) {
        if ($self->{count} > length($self->{text}) * TEXTSPEED + TEXTWAIT) {
            $self->{stage} = 1;
            $self->{count} = 0;
            if ($self->{bunny}) {
                $self->{need_wipe} = 1;
                $self->{sound}->change_music('bunny', 1) if $self->{sound};
            }
            elsif ($self->{art}) {
                $self->{need_wipe} = 1;
            }
        }
        return;
    }
    my $wait = $self->{bunny} ? 1130 : 10;
    if ($skip && $self->{count} > $wait) {
        $self->{done} = 1;
        $self->{action} = 'title';
    }
    return;
}

sub draw {
    my ($self, $fb) = @_;
    if ($self->{stage} == STAGE_CAST) {
        _draw_cast($self, $fb);
        return;
    }
    if ($self->{stage} == 1 && $self->{bunny}) {
        _draw_bunny($self, $fb);
        return;
    }
    if ($self->{stage} == 1 && $self->{art}) {
        fill($fb, 0);
        draw_patch($fb, 0, 0, $self->{art});
        return;
    }
    $$fb = $self->{tiled};
    my $shown = int($self->{count} / TEXTSPEED);
    my ($x, $y) = (10, 10);
    my $i = 0;
    for my $char (split //, $self->{text}) {
        last if $i >= $shown;
        $i++;
        if ($char eq "\n") {
            $x = 10;
            $y += 11;
            next;
        }
        my $code = ord(uc $char);
        if ($char eq ' ' || $code < 33 || $code > 95) {
            $x += 4;
            next;
        }
        my $patch = $self->{font}[$code];
        if (!$patch) {
            $x += 4;
            next;
        }
        my $width = unpack('s<', $patch);
        last if $x + $width > 320;
        draw_patch($fb, $x, $y, $patch);
        $x += $width;
    }
    return;
}

sub _info {
    my ($self) = @_;
    return $Doom::Info::MOBJINFO[$CAST[$self->{castnum}][1]];
}

sub _start_cast {
    my ($self) = @_;
    $self->{need_wipe} = 1;
    $self->{castnum} = 0;
    $self->{castdeath} = 0;
    $self->{stage} = STAGE_CAST;
    $self->{castframes} = 0;
    $self->{castonmelee} = 0;
    $self->{castattacking} = 0;
    my $info = _info($self);
    $self->{caststate} = $info->[MI_SEE];
    $self->{casttics} = $Doom::Info::STATES[$self->{caststate}][2];
    $self->{sound}->change_music('evil', 1) if $self->{sound};
    return;
}

sub _cast_hit {
    my ($self) = @_;
    my $info = _info($self);
    $self->{castdeath} = 1;
    $self->{caststate} = $info->[MI_DEATH];
    $self->{casttics} = $Doom::Info::STATES[$self->{caststate}][2];
    $self->{casttics} = 15 if $self->{casttics} == -1;
    $self->{castframes} = 0;
    $self->{castattacking} = 0;
    return;
}

sub _stop_attack {
    my ($self) = @_;
    $self->{castattacking} = 0;
    $self->{castframes} = 0;
    $self->{caststate} = _info($self)->[MI_SEE];
    return;
}

sub _cast_tick {
    my ($self) = @_;
    $self->{casttics}--;
    return if $self->{casttics} > 0;
    my $st = $Doom::Info::STATES[$self->{caststate}];
    if ($st->[2] == -1 || $st->[4] == S_NULL) {
        $self->{castnum}++;
        $self->{castnum} = 0 if $self->{castnum} >= @CAST;
        $self->{castdeath} = 0;
        $self->{caststate} = _info($self)->[MI_SEE];
        $self->{castframes} = 0;
    }
    elsif ($self->{caststate} == S_PLAY_ATK1) {
        _stop_attack($self);
    }
    else {
        my $nxt = $st->[4];
        $self->{caststate} = $nxt;
        $self->{castframes}++;
        my $sfx = $CAST_SFX{$nxt};
        $self->{sound}->play($sfx) if $sfx && $self->{sound};
    }
    if ($self->{castframes} == 12) {
        $self->{castattacking} = 1;
        my $info = _info($self);
        my $melee = $self->{castonmelee};
        $self->{castonmelee} = $melee ? 0 : 1;
        $self->{caststate} = $melee ? $info->[MI_MELEE] : $info->[MI_MISSILE];
        if ($self->{caststate} == S_NULL) {
            $self->{caststate} = $melee ? $info->[MI_MISSILE] : $info->[MI_MELEE];
        }
    }
    if ($self->{castattacking}) {
        if ($self->{castframes} == 24 || $self->{caststate} == _info($self)->[MI_SEE]) {
            _stop_attack($self);
        }
    }
    $self->{casttics} = $Doom::Info::STATES[$self->{caststate}][2];
    $self->{casttics} = 15 if $self->{casttics} == -1;
    return;
}

sub _cast_print {
    my ($self, $fb, $text) = @_;
    my $width = 0;
    for my $char (split //, $text) {
        my $code = ord(uc $char);
        if ($char eq ' ' || $code < 33 || $code > 95 || !$self->{font}[$code]) {
            $width += 4;
            next;
        }
        $width += unpack('s<', $self->{font}[$code]);
    }
    my $x = 160 - int($width / 2);
    for my $char (split //, $text) {
        my $code = ord(uc $char);
        if ($char eq ' ' || $code < 33 || $code > 95 || !$self->{font}[$code]) {
            $x += 4;
            next;
        }
        my $patch = $self->{font}[$code];
        my $w = unpack('s<', $patch);
        draw_patch($fb, $x, 180, $patch);
        $x += $w;
    }
    return;
}

sub _draw_cast {
    my ($self, $fb) = @_;
    fill($fb, 0);
    draw_patch($fb, 0, 0, $self->{bossback}) if $self->{bossback};
    _cast_print($self, $fb, $CAST[$self->{castnum}][0]);
    my $st = $Doom::Info::STATES[$self->{caststate}] or return;
    my $frame = ($st->[1] || 0) & 0x7FFF;
    my $found = $self->{res} ? Doom::Sprites::lookup_sprite($self->{res}, sprite_name($st->[0]), 0, 0, $frame) : undef;
    return if !$found;
    my $patch = $self->{wad}->cache_lump_num($found->[0]);
    draw_patch($fb, 160, 170, $patch, $found->[1]);
    return;
}

1;
