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
# Janela SDL2. O Perl chama a DLL. Nao ha fonte C neste porte.
# Win32::API e a ponte cdecl; o motor nao entra aqui.

package Doom::Video;

use strict;
use warnings;

use Win32::API;
use Doom::Defs qw(SCREENWIDTH SCREENHEIGHT);
use Doom::Profile;

use constant SDL_INIT_AUDIO           => 0x00000010;
use constant SDL_INIT_VIDEO           => 0x00000020;
use constant SDL_INIT_EVENTS          => 0x00004000;
use constant SDL_WINDOWPOS_CENTERED   => 0x2FFF0000;
use constant SDL_WINDOW_SHOWN         => 0x00000004;
use constant SDL_RENDERER_ACCELERATED => 0x00000002;
use constant SDL_RENDERER_PRESENTVSYNC => 0x00000004;
use constant SDL_PIXELFORMAT_ARGB8888 => 0x16362004;
use constant SDL_TEXTUREACCESS_STREAMING => 1;
use constant SDL_QUIT                 => 0x100;
use constant SDL_KEYDOWN              => 0x300;
use constant SDL_MOUSEMOTION          => 0x400;
use constant SDL_MOUSEBUTTONDOWN      => 0x401;
use constant SDL_MOUSEBUTTONUP        => 0x402;
use constant SDL_WINDOW_FULLSCREEN_DESKTOP => 0x00001001;
use constant KEY_RETURN               => 13;
use constant KEY_KP_ENTER             => 1073741912;
use constant KEY_LALT                 => 1073742050;
use constant KEY_RALT                 => 1073742054;
use constant KMOD_ALT                 => 0x0300;

my $SDL = 'SDL2';

sub _fn {
    my ($name, $args, $ret) = @_;
    my $fn = Win32::API->new($SDL, $name, $args, $ret, '__cdecl');
    die "SDL2 nao exporta $name" if !$fn;
    return $fn;
}

sub new {
    my ($class) = @_;
    my $self = bless {
        window   => 0,
        renderer => 0,
        texture  => 0,
        palette  => "\0" x 768,
        pixels   => "\0" x (SCREENWIDTH * SCREENHEIGHT * 4),
        vsync    => 1,
        down     => {},
        audio    => 0,
        channels => [map { {} } 1 .. 8],
        mdx => 0, mdy => 0, mouseb => 0,
    }, $class;
    $self->_build_pair;
    return $self;
}

sub init {
    my ($self, $scale, $vsync) = @_;
    $scale = 2 if !$scale || $scale < 1;
    $self->{vsync} = $vsync ? 1 : 0;
    $self->{scale} = $scale;
    my $hint = _fn('SDL_SetHint', 'PP', 'I');
    $hint->Call('SDL_RENDER_VSYNC', $self->{vsync} ? '1' : '0') if !$self->{vsync};
    my $init = _fn('SDL_Init', 'I', 'I');
    my $rc = $init->Call(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
    die 'SDL_Init: ' . _error() if $rc != 0;
    my $create = _fn('SDL_CreateWindow', 'PIIIII', 'N');
    my $window = $create->Call(
        'DOOM',
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        SCREENWIDTH * $scale,
        SCREENHEIGHT * $scale,
        SDL_WINDOW_SHOWN,
    );
    die 'SDL_CreateWindow: ' . _error() if !$window;
    my $flags = SDL_RENDERER_ACCELERATED;
    $flags |= SDL_RENDERER_PRESENTVSYNC if $self->{vsync};
    my $rend = _fn('SDL_CreateRenderer', 'NII', 'N');
    my $renderer = $rend->Call($window, -1, $flags);
    if (!$renderer) {
        $renderer = $rend->Call($window, -1, 0);
    }
    die 'SDL_CreateRenderer: ' . _error() if !$renderer;
    _fn('SDL_RenderSetLogicalSize', 'NII', 'I')->Call($renderer, SCREENWIDTH, SCREENHEIGHT);
    if (!$self->{vsync}) {
        my $set = _fn('SDL_RenderSetVSync', 'NI', 'I');
        $set->Call($renderer, 0);
    }
    my $tex = _fn('SDL_CreateTexture', 'NIIII', 'N');
    my $texture = $tex->Call(
        $renderer, SDL_PIXELFORMAT_ARGB8888,
        SDL_TEXTUREACCESS_STREAMING, SCREENWIDTH, SCREENHEIGHT,
    );
    die 'SDL_CreateTexture: ' . _error() if !$texture;
    $self->{window} = $window;
    $self->{renderer} = $renderer;
    $self->{texture} = $texture;
    $self->{poll} = _fn('SDL_PollEvent', 'P', 'I');
    $self->{update} = _fn('SDL_UpdateTexture', 'NNPI', 'I');
    $self->{clear} = _fn('SDL_RenderClear', 'N', 'I');
    $self->{copy} = _fn('SDL_RenderCopy', 'NNPP', 'I');
    $self->{present} = _fn('SDL_RenderPresent', 'N', '');
    $self->{ticks} = _fn('SDL_GetTicks', '', 'I');
    $self->{delay} = _fn('SDL_Delay', 'I', '');
    my $mouse = _fn('SDL_ShowCursor', 'I', 'I');
    $mouse->Call(0);
    $self->_open_audio;
    return;
}

sub set_scale {
    my ($self, $scale) = @_;
    $scale = 1 if !$scale || $scale < 1;
    $scale = 6 if $scale > 6;
    return 0 if $scale == ($self->{scale} || 0) || !$self->{window};
    $self->{scale} = $scale;
    $self->_apply_window_size if !$self->{fullscreen};
    return 1;
}

sub toggle_fullscreen {
    my ($self) = @_;
    return if !$self->{window};
    $self->{full} ||= _fn('SDL_SetWindowFullscreen', 'NI', 'I');
    my $next = $self->{fullscreen} ? 0 : 1;
    my $flag = $next ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0;
    return if $self->{full}->Call($self->{window}, $flag) != 0;
    $self->{fullscreen} = $next;
    $self->_apply_window_size if !$next;
    return;
}

sub _apply_window_size {
    my ($self) = @_;
    return if !$self->{window};
    my $scale = $self->{scale} || 2;
    $self->{set_size} ||= _fn('SDL_SetWindowSize', 'NII', '');
    $self->{set_size}->Call($self->{window}, SCREENWIDTH * $scale, SCREENHEIGHT * $scale);
    my $pos = $self->{set_pos} ||= _fn('SDL_SetWindowPosition', 'NII', '');
    $pos->Call($self->{window}, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    return;
}

sub _open_audio {
    my ($self) = @_;
    my $dev = 0;
    eval {
        my $sub = _fn('SDL_InitSubSystem', 'I', 'I');
        die "audio\n" if $sub->Call(SDL_INIT_AUDIO) != 0;
        my $want = pack('l S C C S S L Q Q', 11025, 0x8010, 1, 0, 512, 0, 0, 0, 0);
        my $have = "\0" x length($want);
        my $open = _fn('SDL_OpenAudioDevice', 'NIPPI', 'I');
        $dev = $open->Call(0, 0, $want, $have, 0) || 0;
        die "audio\n" if !$dev;
        _fn('SDL_PauseAudioDevice', 'II', '')->Call($dev, 0);
        $self->{queue} = _fn('SDL_QueueAudio', 'IPI', 'I');
        $self->{queued} = _fn('SDL_GetQueuedAudioSize', 'I', 'I');
        $self->{clear_q} = eval { _fn('SDL_ClearQueuedAudio', 'I', '') };
    };
    if ($@ || !$dev) {
        $self->{audio} = 0;
        print "sem som\n";
        return;
    }
    $self->{audio} = $dev;
    return;
}

sub silence {
    my ($self) = @_;
    $self->{channels} = [map { {} } 1 .. 8];
    $self->{clear_q}->Call($self->{audio}) if $self->{audio} && $self->{clear_q};
    return;
}

sub mix_pcm {
    my ($self, $pcm, $key) = @_;
    return if !$self->{audio} || !defined $pcm || length($pcm) < 2;
    my $channels = $self->{channels};
    my $name = $key || '';
    for my $ch (@$channels) {
        next if !$ch->{pcm} || ($ch->{name} || '') ne $name || $name eq '';
        next if ($ch->{pos} || 0) >= ($ch->{n} || 0);
        if (($ch->{pos} || 0) < 2000) {
            $ch->{pos} = 0;
            return;
        }
    }
    my $slot = 0;
    my $most = -1;
    for my $i (0 .. $#$channels) {
        my $ch = $channels->[$i];
        if (!$ch->{pcm} || ($ch->{pos} || 0) >= ($ch->{n} || 0)) {
            $slot = $i;
            $most = -1;
            last;
        }
        my $done = $ch->{pos} || 0;
        if ($done > $most) {
            $most = $done;
            $slot = $i;
        }
    }
    $channels->[$slot] = { pcm => $pcm, name => $name, pos => 0, n => int(length($pcm) / 2) };
    return;
}

sub _pump_audio {
    my ($self) = @_;
    return if !$self->{audio};
    my $queued = $self->{queued}->Call($self->{audio}) || 0;
    my $limit = 512 * 2 * 4;
    return if $queued >= $limit;
    my $need = int(($limit - $queued) / 2);
    return if $need < 1;
    my $channels = $self->{channels} || [];
    my $have = 0;
    for my $ch (@$channels) {
        next if !$ch->{pcm};
        my $left = ($ch->{n} || 0) - ($ch->{pos} || 0);
        $have = $left if $left > $have;
    }
    return if $have < 1;
    $need = $have if $have < $need;
    my @mix = (0) x $need;
    for my $ch (@$channels) {
        next if !$ch->{pcm} || ($ch->{pos} || 0) >= ($ch->{n} || 0);
        my $left = $ch->{n} - $ch->{pos};
        my $take = $left < $need ? $left : $need;
        my $pcm = $ch->{pcm};
        my $pos = $ch->{pos};
        for my $i (0 .. $take - 1) {
            my $s = unpack('v', substr($pcm, ($pos + $i) * 2, 2));
            $s -= 65536 if $s >= 32768;
            my $cur = $mix[$i] + int($s * 8 / 15);
            $cur = 32767 if $cur > 32767;
            $cur = -32768 if $cur < -32768;
            $mix[$i] = $cur;
        }
        $ch->{pos} = $pos + $take;
    }
    my $pcm = pack('v*', map { $_ & 65535 } @mix);
    $self->{queue}->Call($self->{audio}, $pcm, length($pcm));
    return;
}

sub _error {
    my $fn = _fn('SDL_GetError', '', 'P');
    my $msg = $fn->Call();
    return defined $msg && $msg ne '' ? $msg : 'erro desconhecido';
}

sub set_palette {
    my ($self, $pal) = @_;
    $pal = substr($pal, 0, 768);
    return if $self->{pair} && $pal eq $self->{palette};
    $self->{palette} = $pal;
    $self->_build_pair;
    return;
}

sub _build_pair {
    my ($self) = @_;
    my $pal = $self->{palette};
    my @lut;
    for my $i (0 .. 255) {
        my $at = $i * 3;
        $lut[$i] = pack(
            'C4',
            ord(substr($pal, $at + 2, 1)),
            ord(substr($pal, $at + 1, 1)),
            ord(substr($pal, $at, 1)),
            255,
        );
    }
    # vec de 16 bits trata o primeiro byte como a parte alta.
    # A chave (p0 << 8) | p1 acompanha essa ordem, em qualquer CPU.
    my @pair;
    $#pair = 65535;
    for my $p0 (0 .. 255) {
        my $a = $lut[$p0];
        my $base = $p0 << 8;
        for my $p1 (0 .. 255) {
            $pair[$base | $p1] = $a . $lut[$p1];
        }
    }
    $self->{pair} = \@pair;
    return;
}

sub upload {
    my ($self, $fb) = @_;
    my $pt = $Doom::Profile::ON ? Doom::Profile::now() : 0;
    my $pair = $self->{pair};
    my $pix = $self->{pixels};
    my $n = (SCREENWIDTH * SCREENHEIGHT) >> 1;
    for (my $i = 0; $i < $n; $i++) {
        substr($pix, $i << 3, 8) = $pair->[vec($fb, $i, 16)];
    }
    $self->{pixels} = $pix;
    Doom::Profile::add('upload', Doom::Profile::now() - $pt) if $pt;
    return;
}

sub present {
    my $pt = $Doom::Profile::ON ? Doom::Profile::now() : 0;
    my ($self) = @_;
    $self->_pump_audio;
    $self->{update}->Call($self->{texture}, 0, $self->{pixels}, SCREENWIDTH * 4);
    $self->{clear}->Call($self->{renderer});
    $self->{copy}->Call($self->{renderer}, $self->{texture}, 0, 0);
    $self->{present}->Call($self->{renderer});
    Doom::Profile::add('present', Doom::Profile::now() - $pt) if $pt;
    Doom::Profile::frame() if $Doom::Profile::ON;
    return;
}

sub pump {
    my ($self) = @_;
    my $event = "\0" x 64;
    my $found = 0;
    while ($self->{poll}->Call($event)) {
        my $type = unpack('V', $event);
        return -1 if $type == SDL_QUIT;
        if ($type == SDL_KEYDOWN || $type == 0x301) {
            my $sym = unpack('V', substr($event, 20, 4));
            my $mod = unpack('v', substr($event, 24, 2));
            my $repeat = ord(substr($event, 13, 1));
            my $alt = ($mod & KMOD_ALT) || $self->{down}{KEY_LALT} || $self->{down}{KEY_RALT};
            if ($type == SDL_KEYDOWN && !$repeat && $alt
                && ($sym == KEY_RETURN || $sym == KEY_KP_ENTER)) {
                $self->{down}{$sym} = 0;
                $self->toggle_fullscreen;
                next;
            }
            $self->{down}{$sym} = $type == SDL_KEYDOWN ? 1 : 0;
            $found = $sym if $type == SDL_KEYDOWN && !$found;
        }
        elsif ($type == SDL_MOUSEMOTION) {
            $self->{mdx} += unpack('l', substr($event, 28, 4));
            $self->{mdy} += unpack('l', substr($event, 32, 4));
        }
        elsif ($type == SDL_MOUSEBUTTONDOWN || $type == SDL_MOUSEBUTTONUP) {
            my $button = ord(substr($event, 16, 1));
            $self->{mouseb} = $type == SDL_MOUSEBUTTONDOWN ? 1 : 0 if $button == 1;
        }
    }
    return $found;
}

sub take_mouse {
    my ($self) = @_;
    my ($x, $y) = ($self->{mdx} || 0, $self->{mdy} || 0);
    $self->{mdx} = 0;
    $self->{mdy} = 0;
    return ($x, $y);
}

sub mouse_fire {
    return $_[0]{mouseb} ? 1 : 0;
}

sub grab_mouse {
    my ($self, $on) = @_;
    $on = $on ? 1 : 0;
    return if ($self->{grabbed} || 0) == $on;
    my $rel = eval { _fn('SDL_SetRelativeMouseMode', 'I', 'I') };
    $rel->Call($on) if $rel;
    my $cur = eval { _fn('SDL_ShowCursor', 'I', 'I') };
    $cur->Call($on ? 0 : 1) if $cur;
    $self->{grabbed} = $on;
    return;
}

sub down {
    my ($self, $sym) = @_;
    return $self->{down}{$sym} ? 1 : 0;
}

sub ticks {
    return $_[0]{ticks}->Call();
}

sub delay {
    $_[0]{delay}->Call($_[1]);
    return;
}

sub shutdown {
    my ($self) = @_;
    return if !$self->{window};
    if ($self->{audio}) {
        eval { _fn('SDL_CloseAudioDevice', 'I', '')->Call($self->{audio}); };
        $self->{audio} = 0;
    }
    _fn('SDL_DestroyTexture', 'N', '')->Call($self->{texture}) if $self->{texture};
    _fn('SDL_DestroyRenderer', 'N', '')->Call($self->{renderer}) if $self->{renderer};
    _fn('SDL_DestroyWindow', 'N', '')->Call($self->{window}) if $self->{window};
    _fn('SDL_Quit', '', '')->Call();
    $self->{window} = 0;
    return;
}

1;
