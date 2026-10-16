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
# Efeitos DS* e a musica do WAD. Igual a doom/sound.py.

package Doom::Sound;

use strict;
use warnings;

use Doom::Mus ();
use File::Temp qw(tempfile);
use Win32::API;

my @DOOM2_MUSIC = qw(
    runnin stalks countd betwee doom the_da shawn ddtblu
    in_cit dead stlks2 theda2 doom2 ddtbl2 runni2 dead2
    stlks3 romero shawn2 messag count2 ddtbl3 ampie theda3
    adrian messg2 romer2 tense shawn3 openin evil ultima
);

sub new {
    my ($class, $wad, $video) = @_;
    return bless {
        wad => $wad, video => $video, cache => {},
        music => '', looping => 0, playing => 0, path => undef, said => 0,
    }, $class;
}

sub at {
    my ($world, $name) = @_;
    my $snd = $world && $world->{sound};
    $snd->play($name) if $snd && $name;
    return;
}

sub play {
    my ($self, $name) = @_;
    my $key = lc $name;
    my $pcm = $self->pcm($name);
    return if !defined $pcm || !$self->{video};
    $self->{video}->mix_pcm($pcm, $key);
    return;
}

sub pcm {
    my ($self, $name) = @_;
    return if !$name;
    my $key = lc $name;
    return $self->{cache}{$key} if exists $self->{cache}{$key};
    my $wad = $self->{wad};
    my $lump = 'DS' . uc substr($key, 0, 6);
    my $n = $wad ? $wad->check_num_for_name($lump) : -1;
    if (!defined $n || $n < 0) {
        $self->{cache}{$key} = undef;
        return;
    }
    my $pcm = _decode($wad->cache_lump_num($n));
    $self->{cache}{$key} = $pcm;
    return $pcm;
}

sub _decode {
    my ($data) = @_;
    return if !defined $data || length($data) < 8;
    my ($fmt, $pad, $rate, $length) = unpack('C C v V', substr($data, 0, 8));
    return if $fmt != 3 || $pad != 0 || $rate <= 0;
    return if $length > length($data) - 8 || $length <= 48;
    my $samples = substr($data, 16, $length - 32);
    return if $samples eq '';
    my $src_n = length($samples);
    my $count = $rate == 11025 ? $src_n : int($src_n * 11025 / $rate);
    $count = 1 if $count < 1;
    my $pcm = '';
    for my $i (0 .. $count - 1) {
        my $at = int($i * $src_n / $count);
        $at = $src_n - 1 if $at >= $src_n;
        my $sample = (ord(substr($samples, $at, 1)) - 128) << 8;
        $pcm .= pack('v', $sample & 65535);
    }
    return $pcm;
}

sub play_title {
    my ($self) = @_;
    return if !$self->{wad};
    if ($self->{wad}->check_num_for_name('MAP01') >= 0) {
        $self->change_music('dm2ttl', 0);
    }
    elsif ($self->{wad}->check_num_for_name('D_INTROA') >= 0) {
        $self->change_music('introa', 0);
    }
    else {
        $self->change_music('intro', 0);
    }
    return;
}

sub play_level {
    my ($self, $episode, $map) = @_;
    return if !$self->{wad};
    my $name;
    if ($self->{wad}->check_num_for_name('MAP01') >= 0) {
        $map = 1 if !$map || $map < 1;
        $name = $DOOM2_MUSIC[($map - 1) % @DOOM2_MUSIC];
    }
    else {
        $name = 'e' . $episode . 'm' . $map;
    }
    $self->change_music($name, 1);
    return;
}

sub change_music {
    my ($self, $name, $looping) = @_;
    return if !$self->{wad} || !$name || lc($name) eq $self->{music};
    my $lump = 'D_' . uc substr($name, 0, 6);
    my $n = $self->{wad}->check_num_for_name($lump);
    return if !defined $n || $n < 0;
    my $midi = Doom::Mus::mus2mid($self->{wad}->cache_lump_num($n));
    return if !defined $midi || $midi eq '';
    $self->stop_music;
    my ($fh, $path) = eval { tempfile('doomXXXX', SUFFIX => '.mid', UNLINK => 0) };
    if ($@ || !$fh) {
        _fail($self);
        return;
    }
    binmode $fh;
    print $fh $midi;
    close $fh;
    $self->{path} = $path;
    $self->{music} = lc $name;
    $self->{looping} = $looping ? 1 : 0;
    my $quoted = $path;
    $quoted =~ s{/}{\\}g;
    $self->_mci('close doommus');
    my $opened = $self->_mci(qq{open "$quoted" type sequencer alias doommus}) == 0
        || $self->_mci(qq{open "$quoted" alias doommus}) == 0;
    $self->{playing} = $opened && $self->_mci('play doommus from 0') == 0 ? 1 : 0;
    if ($self->{playing}) {
        $self->_mci('setaudio doommus volume to ' . int(8 * 1000 / 15));
    }
    else {
        _fail($self);
    }
    return;
}

sub silence {
    my ($self) = @_;
    $self->{video}->silence if $self->{video};
    return;
}

sub update {
    my ($self) = @_;
    return if !$self->{playing} || !$self->{looping} || !$self->{path};
    my $mode = lc $self->_mci_text('status doommus mode');
    $self->_mci('play doommus from 0') if $mode eq 'stopped';
    return;
}

sub stop_music {
    my ($self) = @_;
    $self->_mci('close doommus') if $self->{playing};
    $self->{playing} = 0;
    $self->{music} = '';
    if ($self->{path}) {
        unlink $self->{path};
        $self->{path} = undef;
    }
    return;
}

sub DESTROY {
    my ($self) = @_;
    eval { $self->stop_music if $self->{playing}; };
    return;
}

sub _fail {
    my ($self) = @_;
    return if $self->{said};
    $self->{said} = 1;
    print "sem musica\n";
    return;
}

sub _mci_fn {
    my ($self) = @_;
    return $self->{mci} if exists $self->{mci};
    $self->{mci} = eval { Win32::API->new('winmm', 'mciSendStringA', 'PPNN', 'N') };
    $self->{mci} = undef if $@ || !$self->{mci};
    return $self->{mci};
}

sub _mci {
    my ($self, $cmd) = @_;
    my $fn = $self->_mci_fn;
    return 1 if !$fn;
    my $buf = "\0" x 8;
    my $rc = eval { $fn->Call($cmd, $buf, 0, 0) };
    return 1 if $@ || !defined $rc;
    return $rc + 0;
}

sub _mci_text {
    my ($self, $cmd) = @_;
    my $fn = $self->_mci_fn;
    return '' if !$fn;
    my $buf = "\0" x 64;
    my $rc = eval { $fn->Call($cmd, $buf, 64, 0) };
    return '' if $@ || !defined $rc || $rc != 0;
    $buf =~ s/\0.*//s;
    return $buf;
}

1;
