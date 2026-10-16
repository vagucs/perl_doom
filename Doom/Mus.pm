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
# MUS do WAD vira MIDI. Igual a doom/mus2mid.py.

package Doom::Mus;

use strict;
use warnings;

sub mus2mid {
    my ($mus) = @_;
    return $mus if defined $mus && length($mus) >= 4 && substr($mus, 0, 4) eq 'MThd';
    return if !defined $mus || length($mus) < 16 || substr($mus, 0, 4) ne "MUS\x1a";

    my @controller = (
        0x00, 0x20, 0x01, 0x07, 0x0A, 0x0B, 0x5B, 0x5D,
        0x40, 0x43, 0x78, 0x7B, 0x7E, 0x7F, 0x79,
    );
    my $position = unpack('v', substr($mus, 6, 2));
    my $length = length($mus);
    my $out = {
        body => '',
        queued => 0,
        tracksize => 0,
        velocities => [ (127) x 16 ],
        map => [ (-1) x 16 ],
    };
    my $done = 0;

    my $read = sub {
        return if $position >= $length;
        return ord(substr($mus, $position++, 1));
    };

    while (!$done) {
        while (!$done) {
            my $descriptor = $read->();
            return if !defined $descriptor;
            my $channel = _midi_channel($out, $descriptor & 0x0F);
            my $event = $descriptor & 0x70;

            if ($event == 0x00) {
                my $key = $read->();
                return if !defined $key;
                _write($out, pack('C*', 0x80 | $channel, $key & 0x7F, 0));
            }
            elsif ($event == 0x10) {
                my $key = $read->();
                return if !defined $key;
                if ($key & 0x80) {
                    my $velocity = $read->();
                    return if !defined $velocity;
                    $out->{velocities}[$channel] = $velocity & 0x7F;
                }
                _write($out, pack('C*', 0x90 | $channel, $key & 0x7F, $out->{velocities}[$channel]));
            }
            elsif ($event == 0x20) {
                my $key = $read->();
                return if !defined $key;
                my $wheel = $key * 64;
                _write($out, pack('C*', 0xE0 | $channel, $wheel & 0x7F, ($wheel >> 7) & 0x7F));
            }
            elsif ($event == 0x30) {
                my $controller = $read->();
                return if !defined $controller || $controller < 10 || $controller > 14;
                _write($out, pack('C*', 0xB0 | $channel, $controller[$controller], 0));
            }
            elsif ($event == 0x40) {
                my $controller = $read->();
                my $value = $read->();
                return if !defined $controller || !defined $value;
                if ($controller == 0) {
                    _write($out, pack('C*', 0xC0 | $channel, $value & 0x7F));
                }
                else {
                    return if $controller < 1 || $controller > 9;
                    my $working = ($value & 0x80) ? 0x7F : $value;
                    _write($out, pack('C*', 0xB0 | $channel, $controller[$controller], $working));
                }
            }
            elsif ($event == 0x60) {
                $done = 1;
            }
            else {
                return;
            }
            last if $descriptor & 0x80;
        }

        if (!$done) {
            my $delay = 0;
            while (1) {
                my $working = $read->();
                return if !defined $working;
                $delay = $delay * 128 + ($working & 0x7F);
                last if !($working & 0x80);
            }
            $out->{queued} += $delay;
        }
    }

    _write_time($out, $out->{queued});
    $out->{body} .= "\xFF\x2F\x00";
    $out->{tracksize} += 3;
    my $header = "MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x46" . "MTrk\x00\x00\x00\x00";
    substr($header, 18, 4) = pack('N', $out->{tracksize});
    return $header . $out->{body};
}

sub _write_time {
    my ($out, $time) = @_;
    $time = 0 if !$time || $time < 0;
    my @bytes = ($time & 0x7F);
    $time >>= 7;
    while ($time > 0) {
        unshift @bytes, ($time & 0x7F) | 0x80;
        $time >>= 7;
    }
    my $data = pack('C*', @bytes);
    $out->{body} .= $data;
    $out->{tracksize} += length($data);
    $out->{queued} = 0;
    return;
}

sub _write {
    my ($out, $data) = @_;
    _write_time($out, $out->{queued});
    $out->{body} .= $data;
    $out->{tracksize} += length($data);
    return;
}

sub _midi_channel {
    my ($out, $mus) = @_;
    return 9 if $mus == 15;
    if ($out->{map}[$mus] < 0) {
        my $result = -1;
        for my $v (@{$out->{map}}) {
            $result = $v if $v > $result;
        }
        $result++;
        $result++ if $result == 9;
        $out->{map}[$mus] = $result;
        _write($out, pack('C*', 0xB0 | $result, 0x7B, 0));
    }
    return $out->{map}[$mus];
}

1;
