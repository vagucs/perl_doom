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
# A escolha da dificuldade e as seis vagas. Igual a doom/menu.py.

package Doom::Menu;

use strict;
use warnings;

use Doom::Save;
use Doom::VVideo qw(draw_patch fill);

use constant LINEHEIGHT => 16;
use constant SKULLXOFF => -32;
use constant KEY_ESC => 27;
use constant KEY_ENTER => 13;
use constant KEY_KP_ENTER => 1073741912;
use constant KEY_DOWN => 1073741905;
use constant KEY_UP => 1073741906;
use constant KEY_BACK => 8;
use constant SLOT_X => 80;
use constant SLOT_Y => 54;

sub new {
    my ($class, $wad, $sound) = @_;
    my $nep = 0;
    if ($wad->check_num_for_name('MAP01') < 0) {
        for my $i (1 .. 4) {
            last if $wad->check_num_for_name("E${i}M1") < 0;
            $nep = $i;
        }
    }
    return bless {
        wad => $wad,
        sound => $sound,
        episodes => $nep > 1 ? 1 : 0,
        nep => $nep > 1 ? $nep : 1,
        screen => 'skill',
        item => 2,
        episode => 1,
        skull => 0,
        skull_tics => 8,
    }, $class;
}

sub open {
    my ($self) = @_;
    $self->{screen} = $self->{episodes} ? 'episode' : 'skill';
    $self->{item} = $self->{screen} eq 'skill' ? 2 : 0;
    $self->{skull} = 0;
    $self->{skull_tics} = 8;
    $self->_noise('swtchn');
    return;
}

sub tick {
    my ($self) = @_;
    $self->{skull_tics}--;
    return if $self->{skull_tics} > 0;
    $self->{skull} ^= 1;
    $self->{skull_tics} = 8;
    return;
}

sub choose {
    my ($self, $video, $back) = @_;
    $self->open;
    my $clock = $video->ticks;
    my $debt = 0;
    while (1) {
        my $key = $video->pump;
        return 'quit' if $key < 0;
        my $done = $self->key($key);
        return if defined $done && $done eq 'back';
        return $done if ref $done eq 'HASH';
        my $now = $video->ticks;
        $debt += ($now - $clock) & 0xFFFFFFFF;
        $clock = $now;
        while ($debt >= 28) {
            $debt -= 28;
            $self->tick;
        }
        $debt = 28 if $debt > 28;
        my $fb = $back;
        $self->draw(\$fb);
        $video->upload($fb);
        $self->{sound}->update if $self->{sound};
        $video->present;
        $video->delay(1);
    }
}

sub pick_slot {
    my ($self, $video, $back, $mode, $saver, $suggest) = @_;
    $self->{screen} = $mode eq 'save' ? 'save' : 'load';
    $self->{item} = 0;
    $self->{typing} = 0;
    $self->{edit} = '';
    $self->{suggest} = $suggest || '';
    $self->_read_slots($saver);
    $self->_noise('swtchn');
    my $clock = $video->ticks;
    my $debt = 0;
    while (1) {
        my $key = $video->pump;
        return 'quit' if $key < 0;
        my $done = $self->_slot_key($key);
        return if defined $done && $done eq 'back';
        return $done if ref $done eq 'HASH';
        my $now = $video->ticks;
        $debt += ($now - $clock) & 0xFFFFFFFF;
        $clock = $now;
        while ($debt >= 28) {
            $debt -= 28;
            $self->tick;
        }
        $debt = 28 if $debt > 28;
        my $fb = $back;
        $self->draw(\$fb);
        $video->upload($fb);
        $self->{sound}->update if $self->{sound};
        $video->present;
        $video->delay(1);
    }
}

sub key {
    my ($self, $key) = @_;
    if ($key == KEY_ESC) {
        if ($self->{screen} eq 'skill' && $self->{episodes}) {
            $self->{screen} = 'episode';
            $self->{item} = ($self->{episode} || 1) - 1;
            $self->_noise('swtchx');
            return;
        }
        $self->_noise('swtchx');
        return 'back';
    }
    my $n = $self->_count;
    if ($key == KEY_DOWN) {
        $self->{item} = ($self->{item} + 1) % $n;
        $self->_noise('pstop');
        return;
    }
    if ($key == KEY_UP) {
        $self->{item}--;
        $self->{item} = $n - 1 if $self->{item} < 0;
        $self->_noise('pstop');
        return;
    }
    return if $key != KEY_ENTER && $key != KEY_KP_ENTER;
    $self->_noise('pistol');
    if ($self->{screen} eq 'episode') {
        $self->{episode} = $self->{item} + 1;
        $self->{screen} = 'skill';
        $self->{item} = 2;
        return;
    }
    return {
        skill => $self->{item},
        episode => $self->{episode} || 1,
    };
}

sub draw {
    my ($self, $fb) = @_;
    my $wad = $self->{wad};
    my $x = 48;
    my $y = 63;
    if ($self->{screen} eq 'save' || $self->{screen} eq 'load') {
        $self->_draw_slots($fb);
        return;
    }
    if ($self->{screen} eq 'skill') {
        _patch($fb, $wad, 96, 14, 'M_NEWG');
        _patch($fb, $wad, 54, 38, 'M_SKILL');
        for my $name (qw(M_JKILL M_ROUGH M_HURT M_ULTRA M_NMARE)) {
            _patch($fb, $wad, $x, $y, $name);
            $y += LINEHEIGHT;
        }
    }
    else {
        _patch($fb, $wad, 54, 38, 'M_EPISOD');
        for my $i (1 .. $self->{nep}) {
            _patch($fb, $wad, $x, $y, "M_EPI$i");
            $y += LINEHEIGHT;
        }
    }
    my $skull = $self->{skull} ? 'M_SKULL2' : 'M_SKULL1';
    _patch($fb, $wad, $x + SKULLXOFF, 63 - 5 + $self->{item} * LINEHEIGHT, $skull);
    return;
}

sub _count {
    my ($self) = @_;
    return 6 if $self->{screen} eq 'save' || $self->{screen} eq 'load';
    return 5 if $self->{screen} eq 'skill';
    return $self->{nep} || 1;
}

sub _read_slots {
    my ($self, $saver) = @_;
    $self->{saver} = $saver;
    $self->{slots} = [];
    $self->{slot_ok} = [];
    for my $i (0 .. 5) {
        my ($desc, $ok) = $saver->description($i);
        $self->{slots}[$i] = $desc;
        $self->{slot_ok}[$i] = $ok;
    }
    return;
}

sub _slot_key {
    my ($self, $key) = @_;
    if ($self->{typing}) {
        return $self->_type_key($key);
    }
    if ($key == KEY_ESC) {
        $self->_noise('swtchx');
        return 'back';
    }
    my $n = 6;
    if ($key == KEY_DOWN) {
        $self->{item} = ($self->{item} + 1) % $n;
        $self->_noise('pstop');
        return;
    }
    if ($key == KEY_UP) {
        $self->{item}--;
        $self->{item} = $n - 1 if $self->{item} < 0;
        $self->_noise('pstop');
        return;
    }
    return if $key != KEY_ENTER && $key != KEY_KP_ENTER;
    my $i = $self->{item};
    if ($self->{screen} eq 'load') {
        if (!$self->{slot_ok}[$i]) {
            $self->_noise('oof');
            return;
        }
        $self->_noise('pistol');
        return { load => $i };
    }
    $self->_noise('pistol');
    $self->{typing} = 1;
    my $cur = $self->{slots}[$i] || '';
    if (!$self->{slot_ok}[$i] || $cur eq Doom::Save::EMPTY) {
        $self->{edit} = uc($self->{suggest} || '');
    }
    else {
        $self->{edit} = $cur;
    }
    return;
}

sub _type_key {
    my ($self, $key) = @_;
    if ($key == KEY_ESC) {
        $self->{typing} = 0;
        return;
    }
    if ($key == KEY_BACK) {
        substr($self->{edit}, -1, 1, '') if length $self->{edit};
        return;
    }
    if ($key == KEY_ENTER || $key == KEY_KP_ENTER) {
        $self->{typing} = 0;
        if ($self->{edit} eq '') {
            return;
        }
        $self->_noise('pistol');
        return { save => $self->{item}, desc => $self->{edit} };
    }
    return if $key < 32 || $key > 126;
    return if length($self->{edit}) >= 23;
    $self->{edit} .= uc chr($key);
    return;
}

sub _draw_slots {
    my ($self, $fb) = @_;
    fill($fb, 0);
    my $wad = $self->{wad};
    my $title = $self->{screen} eq 'save' ? 'M_SAVEG' : 'M_LOADG';
    _patch($fb, $wad, 72, 28, $title);
    for my $i (0 .. 5) {
        my $y = SLOT_Y + $i * LINEHEIGHT;
        _slot_border($fb, $wad, SLOT_X, $y);
        my $text = $self->{slots}[$i] || Doom::Save::EMPTY;
        $text = $self->{edit} . '_' if $self->{typing} && $i == $self->{item};
        $self->_text($fb, SLOT_X, $y, $text);
    }
    my $skull = $self->{skull} ? 'M_SKULL2' : 'M_SKULL1';
    _patch(
        $fb, $wad, SLOT_X + SKULLXOFF,
        SLOT_Y - 5 + $self->{item} * LINEHEIGHT, $skull
    );
    return;
}

sub _slot_border {
    my ($fb, $wad, $x, $y) = @_;
    _patch($fb, $wad, $x - 8, $y + 7, 'M_LSLEFT');
    my $xx = $x;
    for (1 .. 24) {
        _patch($fb, $wad, $xx, $y + 7, 'M_LSCNTR');
        $xx += 8;
    }
    _patch($fb, $wad, $xx, $y + 7, 'M_LSRGHT');
    return;
}

sub _text {
    my ($self, $fb, $x, $y, $text) = @_;
    my $wad = $self->{wad};
    for my $ch (split //, uc $text) {
        if ($ch eq ' ') {
            $x += 4;
            next;
        }
        my $n = ord($ch);
        if ($n < 33 || $n > 126) {
            $x += 4;
            next;
        }
        my $name = sprintf('STCFN%03d', $n);
        if ($wad->check_num_for_name($name) < 0) {
            $x += 4;
            next;
        }
        my $patch = $wad->cache_lump_name($name);
        draw_patch($fb, $x, $y, $patch);
        my ($w) = unpack('s<', $patch);
        $x += $w > 4 ? $w : 4;
    }
    return $x;
}

sub _noise {
    my ($self, $name) = @_;
    $self->{sound}->play($name) if $self->{sound};
    return;
}

sub _patch {
    my ($fb, $wad, $x, $y, $name) = @_;
    return if $wad->check_num_for_name($name) < 0;
    draw_patch($fb, $x, $y, $wad->cache_lump_name($name));
    return;
}

1;
