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

my $SDL = 'SDL2';

sub _fn {
    my ($name, $args, $ret) = @_;
    my $fn = Win32::API->new($SDL, $name, $args, $ret, '__cdecl');
    die "SDL2 nao exporta $name" if !$fn;
    return $fn;
}

sub new {
    my ($class) = @_;
    return bless {
        window   => 0,
        renderer => 0,
        texture  => 0,
        palette  => "\0" x 768,
        pixels   => "\0" x (SCREENWIDTH * SCREENHEIGHT * 4),
        vsync    => 1,
        down     => {},
    }, $class;
}

sub init {
    my ($self, $scale, $vsync) = @_;
    $scale = 2 if !$scale || $scale < 1;
    $self->{vsync} = $vsync ? 1 : 0;
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
    return;
}

sub _error {
    my $fn = _fn('SDL_GetError', '', 'P');
    my $msg = $fn->Call();
    return defined $msg && $msg ne '' ? $msg : 'erro desconhecido';
}

sub set_palette {
    my ($self, $pal) = @_;
    $self->{palette} = substr($pal, 0, 768);
    return;
}

sub upload {
    my ($self, $fb) = @_;
    my $pal = $self->{palette};
    my $pix = $self->{pixels};
    my $n = SCREENWIDTH * SCREENHEIGHT;
    for my $i (0 .. $n - 1) {
        my $c = ord(substr($fb, $i, 1));
        my $at = $c * 3;
        substr($pix, $i * 4, 4) = pack(
            'C4',
            ord(substr($pal, $at + 2, 1)),
            ord(substr($pal, $at + 1, 1)),
            ord(substr($pal, $at, 1)),
            255,
        );
    }
    $self->{pixels} = $pix;
    return;
}

sub present {
    my ($self) = @_;
    $self->{update}->Call($self->{texture}, 0, $self->{pixels}, SCREENWIDTH * 4);
    $self->{clear}->Call($self->{renderer});
    $self->{copy}->Call($self->{renderer}, $self->{texture}, 0, 0);
    $self->{present}->Call($self->{renderer});
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
            $self->{down}{$sym} = $type == SDL_KEYDOWN ? 1 : 0;
            $found = $sym if $type == SDL_KEYDOWN && !$found;
        }
    }
    return $found;
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
    _fn('SDL_DestroyTexture', 'N', '')->Call($self->{texture}) if $self->{texture};
    _fn('SDL_DestroyRenderer', 'N', '')->Call($self->{renderer}) if $self->{renderer};
    _fn('SDL_DestroyWindow', 'N', '')->Call($self->{window}) if $self->{window};
    _fn('SDL_Quit', '', '')->Call();
    $self->{window} = 0;
    return;
}

1;
