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
# Menu inicial, opcoes, dificuldade e as seis vagas. Igual a doom/menu.py.

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
use constant KEY_LEFT => 1073741904;
use constant KEY_RIGHT => 1073741903;
use constant KEY_MINUS => 45;
use constant KEY_EQUALS => 61;
use constant KEY_PLUS => 43;
use constant KEY_KP_PLUS => 1073741911;
use constant KEY_KP_MINUS => 1073741910;

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
        screen => 'main',
        item => 0,
        episode => 1,
        skull => 0,
        skull_tics => 8,
        screen_size => 7,
        detail => 0,
        scale => 2,
        messages => 1,
        playing => 0,
        at_title => 1,
        nested => 0,
        ask => '',
    }, $class;
}

sub open {
    my ($self) = @_;
    $self->{screen} = 'main';
    $self->{item} = 0;
    $self->{nested} = 0;
    $self->{typing} = 0;
    $self->{ask} = '';
    $self->{skull} = 0;
    $self->{skull_tics} = 8;
    $self->_noise('swtchn');
    return;
}

sub bump_size {
    my ($self, $up) = @_;
    $self->_bump_size($up ? 1 : 0);
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
        if (defined $done) {
            return if !ref $done && $done eq 'back';
            return $done if ref $done eq 'HASH' || $done ne '';
        }
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
    $self->{nested} = 0;
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

sub _plus {
    my ($key) = @_;
    return $key == KEY_EQUALS || $key == KEY_PLUS || $key == KEY_KP_PLUS;
}

sub _minus {
    my ($key) = @_;
    return $key == KEY_MINUS || $key == KEY_KP_MINUS;
}

sub key {
    my ($self, $key) = @_;
    if ($self->{ask}) {
        return $self->_ask_key($key);
    }
    if (($self->{screen} eq 'save' || $self->{screen} eq 'load') && $self->{typing}) {
        return $self->_type_key($key);
    }
    if (_plus($key)) {
        $self->_bump_size(1);
        return;
    }
    if (_minus($key)) {
        $self->_bump_size(0);
        return;
    }
    if ($self->{screen} eq 'save' || $self->{screen} eq 'load') {
        return $self->_slot_key($key);
    }
    if ($self->{screen} eq 'read' || $self->{screen} eq 'read2') {
        return $self->_read_key($key);
    }
    if ($key == KEY_ESC) {
        return $self->_back_key;
    }
    if ($key == KEY_DOWN) {
        $self->_step(1);
        return;
    }
    if ($key == KEY_UP) {
        $self->_step(-1);
        return;
    }
    if ($key == KEY_LEFT || $key == KEY_RIGHT) {
        $self->_slide($key == KEY_RIGHT ? 1 : 0) if $self->_status($self->{item}) == 2;
        return;
    }
    return if $key != KEY_ENTER && $key != KEY_KP_ENTER;
    return $self->_enter;
}

sub _back_key {
    my ($self) = @_;
    if ($self->{screen} eq 'skill' && $self->{episodes}) {
        $self->{screen} = 'episode';
        $self->{item} = ($self->{episode} || 1) - 1;
        $self->_noise('swtchx');
        return;
    }
    if ($self->{screen} ne 'main') {
        $self->{screen} = 'main';
        $self->{item} = 0;
        $self->{typing} = 0;
        $self->_noise('swtchx');
        return;
    }
    $self->_noise('swtchx');
    return $self->{at_title} ? 'quit' : 'back';
}

sub _enter {
    my ($self) = @_;
    my $screen = $self->{screen};
    my $item = $self->{item};
    if ($screen eq 'main') {
        return $self->_main_enter($item);
    }
    if ($screen eq 'options') {
        return $self->_option_enter($item);
    }
    if ($screen eq 'episode') {
        $self->_noise('pistol');
        $self->{episode} = $item + 1;
        $self->{screen} = 'skill';
        $self->{item} = 2;
        return;
    }
    $self->_noise('pistol');
    return {
        skill => $item,
        episode => $self->{episode} || 1,
    };
}

sub _main_enter {
    my ($self, $item) = @_;
    if ($item == 0) {
        $self->_noise('pistol');
        if ($self->{episodes}) {
            $self->{screen} = 'episode';
            $self->{item} = 0;
        }
        else {
            $self->{episode} = 1;
            $self->{screen} = 'skill';
            $self->{item} = 2;
        }
        return;
    }
    if ($item == 1) {
        $self->_noise('pistol');
        $self->{screen} = 'options';
        $self->{item} = 0;
        return;
    }
    if ($item == 2) {
        return $self->_open_slots('load');
    }
    if ($item == 3) {
        if (!$self->{playing}) {
            $self->_noise('oof');
            return;
        }
        return $self->_open_slots('save');
    }
    if ($item == 4) {
        $self->_noise('pistol');
        $self->{screen} = 'read';
        $self->{item} = 0;
        return;
    }
    $self->_noise('pistol');
    $self->{ask} = 'quit';
    return;
}

sub _option_enter {
    my ($self, $item) = @_;
    if ($item == 0) {
        if (!$self->{playing}) {
            $self->_noise('oof');
            return;
        }
        $self->_noise('pistol');
        $self->{ask} = 'endgame';
        return;
    }
    if ($item == 1) {
        $self->{messages} = $self->{messages} ? 0 : 1;
        $self->_noise('pistol');
        print $self->{messages} ? "mensagens ligadas\n" : "mensagens desligadas\n";
        return;
    }
    if ($item == 2) {
        $self->_toggle_detail;
        return;
    }
    if ($item == 3) {
        $self->_bump_size(1);
        return;
    }
    if ($item == 5) {
        $self->_bump_scale(1);
        return;
    }
    return;
}

sub _open_slots {
    my ($self, $mode) = @_;
    if (!$self->{saver}) {
        $self->_noise('oof');
        return;
    }
    $self->_noise('pistol');
    $self->{screen_was} = $self->{item};
    $self->{nested} = 1;
    $self->{typing} = 0;
    $self->{edit} = '';
    $self->{screen} = $mode;
    $self->{item} = 0;
    $self->_read_slots($self->{saver});
    return;
}

sub _read_key {
    my ($self, $key) = @_;
    if ($key == KEY_ESC) {
        $self->{screen} = 'main';
        $self->{item} = 4;
        $self->_noise('swtchx');
        return;
    }
    return if $key != KEY_ENTER && $key != KEY_KP_ENTER;
    $self->_noise('pistol');
    my $wad = $self->{wad};
    if ($self->{screen} eq 'read' && $wad->check_num_for_name('HELP2') >= 0
        && $wad->check_num_for_name('HELP1') >= 0) {
        $self->{screen} = 'read2';
        return;
    }
    $self->{screen} = 'main';
    $self->{item} = 4;
    return;
}

sub _ask_key {
    my ($self, $key) = @_;
    if ($key == KEY_ESC || $key == ord('n') || $key == ord('N')) {
        $self->{ask} = '';
        $self->_noise('swtchx');
        return;
    }
    if ($key == ord('y') || $key == ord('Y') || $key == ord('s') || $key == ord('S')) {
        my $act = $self->{ask};
        $self->{ask} = '';
        return $act;
    }
    return;
}

sub _step {
    my ($self, $dir) = @_;
    my $n = $self->_count;
    my $i = $self->{item};
    for (1 .. $n) {
        $i = ($i + $dir) % $n;
        $i += $n if $i < 0;
        next if $self->_status($i) < 0;
        $self->{item} = $i;
        $self->_noise('pstop');
        return;
    }
    return;
}

sub _slide {
    my ($self, $up) = @_;
    return if $self->{screen} ne 'options';
    my $item = $self->{item};
    $self->_toggle_detail if $item == 2;
    $self->_bump_size($up) if $item == 3;
    $self->_bump_scale($up) if $item == 5;
    return;
}

sub _bump_size {
    my ($self, $up) = @_;
    my $n = $self->{screen_size};
    if ($up) {
        return if $n >= 8;
        $self->{screen_size} = $n + 1;
    }
    else {
        return if $n <= 0;
        $self->{screen_size} = $n - 1;
    }
    $self->_noise('stnmov');
    $self->{on_view}->() if $self->{on_view};
    return;
}

sub _bump_scale {
    my ($self, $up) = @_;
    my $n = $self->{scale} || 2;
    if ($up) {
        return if $n >= 6;
        $self->{scale} = $n + 1;
    }
    else {
        return if $n <= 1;
        $self->{scale} = $n - 1;
    }
    $self->_noise('stnmov');
    $self->{on_scale}->() if $self->{on_scale};
    return;
}

sub _toggle_detail {
    my ($self) = @_;
    $self->{detail} = $self->{detail} ? 0 : 1;
    $self->_noise('stnmov');
    print $self->{detail} ? "detalhe baixo\n" : "detalhe alto\n";
    $self->{on_view}->() if $self->{on_view};
    return;
}

sub draw {
    my ($self, $fb) = @_;
    my $wad = $self->{wad};
    my $screen = $self->{screen};
    if ($self->{ask}) {
        $self->_text(
            $fb, 48, 80,
            $self->{ask} eq 'quit' ? 'SAIR? (S/N)' : 'TERMINAR? (S/N)'
        );
        return;
    }
    if ($screen eq 'save' || $screen eq 'load') {
        $self->_draw_slots($fb);
        return;
    }
    if ($screen eq 'read' || $screen eq 'read2') {
        fill($fb, 0);
        my $lump = 'CREDIT';
        if ($screen eq 'read' && $wad->check_num_for_name('HELP2') >= 0) {
            $lump = 'HELP2';
        }
        elsif ($wad->check_num_for_name('HELP1') >= 0) {
            $lump = 'HELP1';
        }
        elsif ($wad->check_num_for_name('HELP') >= 0) {
            $lump = 'HELP';
        }
        _patch($fb, $wad, 0, 0, $lump);
        return;
    }
    my ($x, $y0, @names);
    if ($screen eq 'main') {
        _patch($fb, $wad, 94, 2, 'M_DOOM');
        $x = 97;
        $y0 = 64;
        @names = qw(M_NGAME M_OPTION M_LOADG M_SAVEG M_RDTHIS M_QUITG);
    }
    elsif ($screen eq 'options') {
        _patch($fb, $wad, 108, 15, 'M_OPTTTL');
        $x = 60;
        $y0 = 37;
        @names = ('M_ENDGAM', 'M_MESSG', 'M_DETAIL', 'M_SCRNSZ', '', '', '');
    }
    elsif ($screen eq 'skill') {
        _patch($fb, $wad, 96, 14, 'M_NEWG');
        _patch($fb, $wad, 54, 38, 'M_SKILL');
        $x = 48;
        $y0 = 63;
        @names = qw(M_JKILL M_ROUGH M_HURT M_ULTRA M_NMARE);
    }
    else {
        _patch($fb, $wad, 54, 38, 'M_EPISOD');
        $x = 48;
        $y0 = 63;
        @names = map { "M_EPI$_" } 1 .. $self->{nep};
    }
    my $y = $y0;
    for my $name (@names) {
        _patch($fb, $wad, $x, $y, $name) if $name;
        $y += LINEHEIGHT;
    }
    if ($screen eq 'options') {
        my $msg = $self->{messages} ? 'M_MSGON' : 'M_MSGOFF';
        _patch($fb, $wad, $x + 120, $y0 + LINEHEIGHT, $msg);
        my $det = $self->{detail} ? 'M_GDLOW' : 'M_GDHIGH';
        _patch($fb, $wad, $x + 175, $y0 + LINEHEIGHT * 2, $det);
        $self->_text($fb, $x, $y0 + LINEHEIGHT * 5, 'RESOLUCAO');
        my $px = ($self->{scale} || 2) * 320;
        my $py = ($self->{scale} || 2) * 200;
        $self->_text($fb, $x + 96, $y0 + LINEHEIGHT * 5, $px . 'X' . $py);
        $self->_thermo($fb, $x, $y0 + LINEHEIGHT * 4, 9, $self->{screen_size});
        $self->_thermo($fb, $x, $y0 + LINEHEIGHT * 6, 6, ($self->{scale} || 2) - 1);
    }
    my $skull = $self->{skull} ? 'M_SKULL2' : 'M_SKULL1';
    _patch($fb, $wad, $x + SKULLXOFF, $y0 - 5 + $self->{item} * LINEHEIGHT, $skull);
    return;
}

sub _thermo {
    my ($self, $fb, $x, $y, $width, $dot) = @_;
    my $wad = $self->{wad};
    my $xx = $x;
    _patch($fb, $wad, $xx, $y, 'M_THERML');
    $xx += 8;
    for (1 .. $width) {
        _patch($fb, $wad, $xx, $y, 'M_THERMM');
        $xx += 8;
    }
    _patch($fb, $wad, $xx, $y, 'M_THERMR');
    $dot = 0 if $dot < 0;
    $dot = $width - 1 if $dot > $width - 1;
    _patch($fb, $wad, $x + 8 + $dot * 8, $y, 'M_THERMO');
    return;
}

sub _count {
    my ($self) = @_;
    return 6 if $self->{screen} eq 'save' || $self->{screen} eq 'load' || $self->{screen} eq 'main';
    return 7 if $self->{screen} eq 'options';
    return 5 if $self->{screen} eq 'skill';
    return 1 if $self->{screen} eq 'read' || $self->{screen} eq 'read2';
    return $self->{nep} || 1;
}

sub _status {
    my ($self, $i) = @_;
    return -1 if $self->{screen} eq 'options' && ($i == 4 || $i == 6);
    return 2 if $self->{screen} eq 'options' && ($i == 2 || $i == 3 || $i == 5);
    return 1;
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
        if ($self->{nested}) {
            $self->{screen} = 'main';
            $self->{item} = $self->{screen_was} || 0;
            $self->{typing} = 0;
            return;
        }
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
