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
# Tela de fim de fase. Igual a doom/wi_stuff.py na contagem.

package Doom::Wi;

use strict;
use warnings;

use Doom::VVideo qw(draw_patch);

use constant STAT_COUNT => 0;
use constant SHOW_NEXT => 1;
use constant NO_STATE => -1;
use constant TICRATE => 35;

my @PARS = (
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 30, 75, 120, 90, 165, 180, 180, 30, 165],
    [0, 90, 90, 90, 120, 90, 360, 240, 30, 170],
    [0, 90, 45, 90, 150, 90, 90, 165, 30, 135],
);
my @NODES = (
    [[185, 164], [148, 143], [69, 122], [209, 102], [116, 89], [166, 55], [71, 56], [135, 29], [71, 24]],
    [[254, 25], [97, 50], [188, 64], [128, 78], [214, 92], [133, 130], [208, 136], [148, 140], [235, 158]],
    [[156, 168], [48, 154], [174, 95], [265, 75], [130, 48], [279, 23], [198, 48], [140, 25], [281, 136]],
);

sub new {
    my ($class, $wad, $sound, $st) = @_;
    my $commercial = $wad->check_num_for_name('MAP01') >= 0 ? 1 : 0;
    my $episode = $st->{episode} || 1;
    my $map = $st->{map} || 1;
    my $secret = $st->{secret} ? 1 : 0;
    my ($next_i, $nextmap) = _next($commercial, $episode, $map, $secret);
    my $self = bless {
        wad => $wad, sound => $sound, commercial => $commercial,
        epsd => $episode - 1, last => $map - 1, next => $next_i, nextmap => $nextmap,
        maxkills => $st->{totalkills} || 0, maxitems => $st->{totalitems} || 0,
        maxsecret => $st->{totalsecret} || 0,
        skills => $st->{kills} || 0, sitems => $st->{items} || 0, ssecret => $st->{secrets} || 0,
        stime => $st->{time} || 0,
        partime => _par($commercial, $episode, $map),
        state => STAT_COUNT, sp => 1, accelerate => 0,
        kills => -1, items => -1, secret => -1, time => -1, par => -1,
        pause => TICRATE, count => 0, bg => 0, pointer => 0, done => 0, sang => 0,
        patches => {}, numbers => [], names => [],
    }, $class;
    my %names = (
        finished => 'WIF', entering => 'WIENTER', kills => 'WIOSTK', items => 'WIOSTI',
        secret => 'WISCRT2', percent => 'WIPCNT', colon => 'WICOLON', time => 'WITIME',
        par => 'WIPAR', sucks => 'WISUCKS', minus => 'WIMINUS', splat => 'WISPLAT',
        yah0 => 'WIURH0', yah1 => 'WIURH1',
    );
    for my $key (keys %names) {
        $self->{patches}{$key} = _lump($wad, $names{$key});
    }
    $self->{numbers} = [map { _lump($wad, "WINUM$_") } 0 .. 9];
    my $maps = $commercial ? 32 : 9;
    for my $i (0 .. $maps - 1) {
        my $name = $commercial ? sprintf('CWILV%02d', $i) : 'WILV' . ($episode - 1) . $i;
        push @{$self->{names}}, _lump($wad, $name);
    }
    my $bg = $commercial || $episode == 4 ? 'INTERPIC' : 'WIMAP' . ($episode - 1);
    $self->{background} = _lump($wad, $bg) || _lump($wad, 'INTERPIC');
    $self->{anims} = [];
    $self->{bcnt} = 0;
    if (!$commercial && $episode >= 1 && $episode <= 3) {
        my @spec = (
            [
                [0, 11, 3, 224, 104], [0, 11, 3, 184, 160], [0, 11, 3, 112, 136],
                [0, 11, 3, 72, 112], [0, 11, 3, 88, 96], [0, 11, 3, 64, 48],
                [0, 11, 3, 192, 40], [0, 11, 3, 136, 16], [0, 11, 3, 80, 16],
                [0, 11, 3, 64, 24],
            ],
            [
                [2, 11, 1, 128, 136, 1], [2, 11, 1, 128, 136, 2], [2, 11, 1, 128, 136, 3],
                [2, 11, 1, 128, 136, 4], [2, 11, 1, 128, 136, 5], [2, 11, 1, 128, 136, 6],
                [2, 11, 1, 128, 136, 7], [0, 11, 3, 192, 144, 8], [2, 11, 1, 128, 136, 8],
            ],
            [
                [0, 11, 3, 104, 168], [0, 11, 3, 40, 136], [0, 11, 3, 160, 96],
                [0, 11, 3, 104, 80], [0, 11, 3, 120, 32], [0, 8, 3, 40, 0],
            ],
        );
        my $list = $spec[$episode - 1];
        for my $j (0 .. $#$list) {
            my $sp = $list->[$j];
            my @patches;
            for my $i (0 .. $sp->[2] - 1) {
                my $name = sprintf('WIA%d%02d%02d', $episode - 1, $j, $i);
                push @patches, _lump($wad, $name);
            }
            push @{$self->{anims}}, {
                type => $sp->[0], period => $sp->[1], x => $sp->[3], y => $sp->[4],
                data => $sp->[5] || 0, patches => \@patches, ctr => -1, nexttic => 1 + int(rand($sp->[1] || 1)),
            };
        }
    }
    return $self;
}

sub tick {
    my ($self, $go) = @_;
    $self->{bg}++;
    $self->{bcnt}++;
    for my $a (@{$self->{anims} || []}) {
        next if $self->{bcnt} != $a->{nexttic};
        if ($a->{type} == 0) {
            $a->{ctr}++;
            $a->{ctr} = 0 if $a->{ctr} >= @{$a->{patches}};
            $a->{nexttic} = $self->{bcnt} + $a->{period};
        }
        elsif ($self->{next} == $a->{data}) {
            $a->{ctr}++ if $a->{ctr} < @{$a->{patches}} - 1;
            $a->{nexttic} = $self->{bcnt} + $a->{period};
        }
    }
    if ($self->{bg} == 1) {
        my $song = $self->{commercial} ? 'dm2int' : 'inter';
        $self->{sound}->change_music($song, 1) if $self->{sound};
    }
    $self->{accelerate} = 1 if $go;
    if ($self->{state} == STAT_COUNT) {
        _stats($self);
    }
    elsif ($self->{state} == SHOW_NEXT) {
        if (--$self->{count} == 0 || $self->{accelerate}) {
            $self->{state} = NO_STATE;
            $self->{accelerate} = 0;
            $self->{count} = 10;
        }
        else {
            $self->{pointer} = ($self->{count} & 31) < 20 ? 1 : 0;
        }
    }
    elsif (--$self->{count} == 0) {
        $self->{done} = 1;
    }
    return;
}

sub draw {
    my ($self, $fb) = @_;
    draw_patch($fb, 0, 0, $self->{background}) if $self->{background};
    for my $a (@{$self->{anims} || []}) {
        next if $a->{ctr} < 0;
        my $patch = $a->{patches}[$a->{ctr}];
        draw_patch($fb, $a->{x}, $a->{y}, $patch) if $patch;
    }
    if ($self->{state} == STAT_COUNT) {
        _draw_stats($self, $fb);
    }
    else {
        _draw_next($self, $fb);
    }
    return;
}

sub _next {
    my ($commercial, $episode, $map, $secret) = @_;
    if ($commercial) {
        my $idx = $map;
        $idx = 30 if $secret && $map == 15;
        $idx = 31 if $secret && $map == 31;
        $idx = 15 if !$secret && ($map == 31 || $map == 32);
        return ($idx, $idx + 1);
    }
    return (-1, 0) if $map == 8 && !$secret;
    if ($map == 9 && !$secret) {
        my %back = (1 => 3, 2 => 5, 3 => 6, 4 => 2);
        my $idx = $back{$episode} // 0;
        return ($idx, $idx + 1);
    }
    my $idx = $secret ? 8 : $map;
    return ($idx, $idx + 1);
}

sub _par {
    my ($commercial, $episode, $map) = @_;
    return TICRATE * 30 if $commercial;
    return TICRATE * $PARS[$episode][$map] if $episode >= 1 && $episode <= 3 && $map >= 1 && $map <= 9;
    return TICRATE * 30;
}

sub _pct {
    my ($value, $max) = @_;
    $max = 1 if $max < 1;
    return int($value * 100 / $max);
}

sub _noise {
    my ($self, $name) = @_;
    $self->{sound}->play($name) if $self->{sound};
    return;
}

sub _stats {
    my ($self) = @_;
    if ($self->{accelerate} && $self->{sp} != 10) {
        $self->{accelerate} = 0;
        $self->{kills} = _pct($self->{skills}, $self->{maxkills});
        $self->{items} = _pct($self->{sitems}, $self->{maxitems});
        $self->{secret} = _pct($self->{ssecret}, $self->{maxsecret});
        $self->{time} = int($self->{stime} / TICRATE);
        $self->{par} = int($self->{partime} / TICRATE);
        _noise($self, 'barexp');
        $self->{sp} = 10;
        return;
    }
    if ($self->{sp} & 1) {
        return if --$self->{pause} != 0;
        $self->{sp}++;
        $self->{pause} = TICRATE;
        $self->{kills} = 0 if $self->{sp} == 2;
        $self->{items} = 0 if $self->{sp} == 4;
        $self->{secret} = 0 if $self->{sp} == 6;
        if ($self->{sp} == 8) {
            $self->{time} = 0;
            $self->{par} = 0;
        }
        return;
    }
    if ($self->{sp} == 10) {
        return if !$self->{accelerate};
        _noise($self, 'wpnup');
        if ($self->{commercial} || $self->{next} < 0) {
            $self->{state} = NO_STATE;
            $self->{count} = 10;
        }
        else {
            $self->{state} = SHOW_NEXT;
            $self->{count} = 4 * TICRATE;
        }
        $self->{accelerate} = 0;
        return;
    }
    _noise($self, 'pistol') if ($self->{bg} & 3) == 0;
    if ($self->{sp} == 8) {
        $self->{time} += 3;
        $self->{par} += 3;
        my $limit = int($self->{stime} / TICRATE);
        my $plimit = int($self->{partime} / TICRATE);
        $self->{time} = $limit if $self->{time} > $limit;
        $self->{par} = $plimit if $self->{par} > $plimit;
        _finish($self) if $self->{time} >= $limit && $self->{par} >= $plimit;
        return;
    }
    my $field = $self->{sp} == 2 ? 'kills' : ($self->{sp} == 4 ? 'items' : 'secret');
    my $got = $field eq 'kills' ? $self->{skills} : ($field eq 'items' ? $self->{sitems} : $self->{ssecret});
    my $max = $field eq 'kills' ? $self->{maxkills} : ($field eq 'items' ? $self->{maxitems} : $self->{maxsecret});
    my $target = _pct($got, $max);
    $self->{$field} += 2;
    if ($self->{$field} >= $target) {
        $self->{$field} = $target;
        _finish($self);
    }
    return;
}

sub _finish {
    my ($self) = @_;
    _noise($self, 'barexp');
    $self->{sp}++;
    return;
}

sub _draw_stats {
    my ($self, $fb) = @_;
    _finished($self, $fb);
    my $y = 50;
    for my $row (
        ['kills', $self->{kills}],
        ['items', $self->{items}],
        ['secret', $self->{secret}],
    ) {
        draw_patch($fb, 50, $y, $self->{patches}{$row->[0]}) if $self->{patches}{$row->[0]};
        _percent($self, $fb, 270, $y, $row->[1]);
        $y += 24;
    }
    draw_patch($fb, 16, 168, $self->{patches}{time}) if $self->{patches}{time};
    _time($self, $fb, 144, 168, $self->{time});
    if ($self->{epsd} < 3) {
        draw_patch($fb, 176, 168, $self->{patches}{par}) if $self->{patches}{par};
        _time($self, $fb, 304, 168, $self->{par});
    }
    return;
}

sub _finished {
    my ($self, $fb) = @_;
    my $y = 2;
    my $name = $self->{names}[$self->{last}];
    if ($name) {
        my ($w, $h) = _size($name);
        draw_patch($fb, int((320 - $w) / 2), $y, $name);
        $y += int(5 * $h / 4);
    }
    my $fin = $self->{patches}{finished};
    if ($fin) {
        my ($w) = _size($fin);
        draw_patch($fb, int((320 - $w) / 2), $y, $fin);
    }
    return;
}

sub _draw_next {
    my ($self, $fb) = @_;
    $self->{pointer} = 1 if $self->{state} == NO_STATE;
    if (!$self->{commercial} && $self->{epsd} < 3 && $self->{next} >= 0) {
        my $last = $self->{last} == 8 ? $self->{next} - 1 : $self->{last};
        for my $i (0 .. $last) {
            _node($self, $fb, $i, [$self->{patches}{splat}]);
        }
        if ($self->{pointer}) {
            _node($self, $fb, $self->{next}, [$self->{patches}{yah0}, $self->{patches}{yah1}]);
        }
    }
    return if $self->{next} < 0;
    my $y = 2;
    my $enter = $self->{patches}{entering};
    if ($enter) {
        my ($w, $h) = _size($enter);
        draw_patch($fb, int((320 - $w) / 2), $y, $enter);
        $y += int(5 * $h / 4);
    }
    my $name = $self->{next} >= 0 ? $self->{names}[$self->{next}] : undef;
    if ($name) {
        my ($w) = _size($name);
        draw_patch($fb, int((320 - $w) / 2), $y, $name);
    }
    return;
}

sub _node {
    my ($self, $fb, $number, $patches) = @_;
    my $nodes = $NODES[$self->{epsd}] || [];
    my $node = $nodes->[$number];
    return if !$node;
    for my $patch (@$patches) {
        next if !$patch;
        my ($w, $h, $left, $top) = _size($patch);
        my $x = $node->[0] - $left;
        my $y = $node->[1] - $top;
        next if $x < 0 || $x + $w >= 320 || $y < 0 || $y + $h >= 200;
        draw_patch($fb, $node->[0], $node->[1], $patch);
        return;
    }
    return;
}

sub _percent {
    my ($self, $fb, $x, $y, $value) = @_;
    return if !defined $value || $value < 0;
    draw_patch($fb, $x, $y, $self->{patches}{percent}) if $self->{patches}{percent};
    _number($self, $fb, $x, $y, $value, -1);
    return;
}

sub _number {
    my ($self, $fb, $x, $y, $n, $digits) = @_;
    my ($width) = _size($self->{numbers}[0]);
    $width = 8 if $width < 1;
    my $negative = $n < 0;
    $n = abs($n || 0);
    $digits = ($n == 0 ? 1 : length($n)) if $digits < 0;
    while ($digits-- > 0) {
        $x -= $width;
        draw_patch($fb, $x, $y, $self->{numbers}[$n % 10]);
        $n = int($n / 10);
    }
    if ($negative && $self->{patches}{minus}) {
        $x -= 8;
        draw_patch($fb, $x, $y, $self->{patches}{minus});
    }
    return $x;
}

sub _time {
    my ($self, $fb, $x, $y, $t) = @_;
    return if !defined $t || $t < 0;
    if ($t > 61 * 59) {
        my $p = $self->{patches}{sucks};
        if ($p) {
            my ($w) = _size($p);
            draw_patch($fb, $x - $w, $y, $p);
        }
        return;
    }
    my $div = 1;
    while (1) {
        my $n = int($t / $div) % 60;
        $x = _number($self, $fb, $x, $y, $n, 2) - 8;
        $div *= 60;
        my $more = int($t / $div);
        if (($div == 60 || $more > 0) && $self->{patches}{colon}) {
            draw_patch($fb, $x, $y, $self->{patches}{colon});
        }
        last if $more <= 0;
    }
    return;
}

sub _size {
    my ($patch) = @_;
    return (0, 0, 0, 0) if !defined $patch || length($patch) < 8;
    return unpack('s<4', $patch);
}

sub _lump {
    my ($wad, $name) = @_;
    my $n = $wad->check_num_for_name($name);
    return if !defined $n || $n < 0;
    return $wad->cache_lump_num($n);
}

1;
