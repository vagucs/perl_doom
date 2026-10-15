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
# Texturas, flats e colormap. Igual a doom/r_data.py.

package Doom::RData;

use strict;
use warnings;

use Doom::Defs qw(FRACUNIT);

sub _i32 {
    my $v = unpack('V', substr($_[0], $_[1], 4));
    return $v >= 0x80000000 ? $v - 4294967296 : $v;
}

sub _i16 {
    my $v = unpack('v', substr($_[0], $_[1], 2));
    return $v >= 32768 ? $v - 65536 : $v;
}

sub _name8 {
    my $raw = substr($_[0], $_[1], 8);
    $raw =~ s/\x00.*//s;
    $raw =~ s/\s+$//;
    return uc $raw;
}

sub new {
    my ($class, $wad) = @_;
    return bless {
        wad => $wad,
        textures => [],
        tex_index => {},
        flats_first => 0,
        flats_last => 0,
        flattranslation => [],
        texturetranslation => [],
        colormaps => '',
        skytexture => 0,
        skyflatnum => 0,
    }, $class;
}

sub init {
    my ($self) = @_;
    $self->_init_textures;
    $self->_init_flats;
    $self->{colormaps} = $self->{wad}->cache_lump_name('COLORMAP');
    $self->{skyflatnum} = $self->flat_num_for_name('F_SKY1');
    $self->{skytexture} = $self->texture_num_for_name('SKY1');
    return;
}

sub colormap {
    my ($self, $level) = @_;
    $level = 0 if $level < 0;
    $level = 32 if $level > 32;
    return substr($self->{colormaps}, $level * 256, 256);
}

sub _init_flats {
    my ($self) = @_;
    $self->{flats_first} = $self->{wad}->get_num_for_name('F_START') + 1;
    $self->{flats_last} = $self->{wad}->get_num_for_name('F_END') - 1;
    my $n = $self->{flats_last} - $self->{flats_first} + 1;
    $self->{flattranslation} = [0 .. $n - 1];
    return;
}

sub flat_num_for_name {
    my ($self, $name) = @_;
    my $i = $self->{wad}->check_num_for_name($name);
    return 0 if $i < 0;
    return $i - $self->{flats_first};
}

sub flat_lump {
    my ($self, $flatnum) = @_;
    $flatnum = 0 if $flatnum < 0;
    my $n = $self->{flats_last} - $self->{flats_first} + 1;
    $flatnum = 0 if $flatnum >= $n;
    return $self->{flats_first} + $self->{flattranslation}[$flatnum];
}

sub _init_textures {
    my ($self) = @_;
    my $pnames = $self->{wad}->cache_lump_name('PNAMES');
    my $nummappatches = _i32($pnames, 0);
    my @patchlookup;
    for my $i (0 .. $nummappatches - 1) {
        push @patchlookup, $self->{wad}->check_num_for_name(_name8($pnames, 4 + $i * 8));
    }
    my $maptex1 = $self->{wad}->cache_lump_name('TEXTURE1');
    my $numtextures1 = _i32($maptex1, 0);
    my $maptex2 = '';
    my $numtextures2 = 0;
    if ($self->{wad}->check_num_for_name('TEXTURE2') >= 0) {
        $maptex2 = $self->{wad}->cache_lump_name('TEXTURE2');
        $numtextures2 = _i32($maptex2, 0);
    }
    for my $i (0 .. $numtextures1 + $numtextures2 - 1) {
        my ($offset, $src);
        if ($i < $numtextures1) {
            $offset = _i32($maptex1, 4 + $i * 4);
            $src = $maptex1;
        }
        else {
            $offset = _i32($maptex2, 4 + ($i - $numtextures1) * 4);
            $src = $maptex2;
        }
        my $name = _name8($src, $offset);
        my $width = _i16($src, $offset + 12);
        my $height = _i16($src, $offset + 14);
        my $patchcount = _i16($src, $offset + 20);
        my $tex = {
            name => $name, width => $width, height => $height,
            patches => [], widthmask => 0,
            col_lump => [], col_ofs => [], composite => undef,
        };
        my $poff = $offset + 22;
        for my $p (0 .. $patchcount - 1) {
            my $ox = _i16($src, $poff);
            my $oy = _i16($src, $poff + 2);
            my $pidx = _i16($src, $poff + 4);
            $poff += 10;
            my $lump = ($pidx >= 0 && $pidx < @patchlookup) ? $patchlookup[$pidx] : -1;
            push @{$tex->{patches}}, { originx => $ox, originy => $oy, patch => $lump };
        }
        my $j = 1;
        $j *= 2 while $j * 2 <= $width;
        $tex->{widthmask} = $j - 1;
        $tex->{col_lump} = [(-1) x $width];
        $tex->{col_ofs} = [(0) x $width];
        $self->{tex_index}{$name} = scalar @{$self->{textures}};
        push @{$self->{textures}}, $tex;
    }
    for my $tex (@{$self->{textures}}) {
        $self->_generate_lookup($tex);
    }
    return;
}

sub _generate_lookup {
    my ($self, $tex) = @_;
    my $width = $tex->{width};
    my @patchcount = (0) x $width;
    for my $mp (@{$tex->{patches}}) {
        next if $mp->{patch} < 0;
        my $pdata = $self->{wad}->cache_lump_num($mp->{patch});
        my $pw = _i16($pdata, 0);
        my $x1 = $mp->{originx};
        my $x2 = $x1 + $pw;
        my $x = $x1 < 0 ? 0 : $x1;
        $x2 = $width if $x2 > $width;
        while ($x < $x2) {
            $patchcount[$x]++;
            $tex->{col_lump}[$x] = $mp->{patch};
            $tex->{col_ofs}[$x] = unpack('V', substr($pdata, 8 + ($x - $mp->{originx}) * 4, 4));
            $x++;
        }
    }
    for my $x (0 .. $width - 1) {
        $tex->{col_lump}[$x] = -1 if $patchcount[$x] > 1;
    }
    return;
}

sub _generate_composite {
    my ($self, $tex) = @_;
    return if defined $tex->{composite};
    my $buf = "\0" x ($tex->{width} * $tex->{height});
    for my $mp (@{$tex->{patches}}) {
        next if $mp->{patch} < 0;
        my $pdata = $self->{wad}->cache_lump_num($mp->{patch});
        my $pw = _i16($pdata, 0);
        my $x1 = $mp->{originx};
        my $x2 = $x1 + $pw;
        $x2 = $tex->{width} if $x2 > $tex->{width};
        my $x = $x1 < 0 ? 0 : $x1;
        while ($x < $x2) {
            my $colofs = unpack('V', substr($pdata, 8 + ($x - $mp->{originx}) * 4, 4));
            $self->_draw_column_in_cache($pdata, $colofs, \$buf, $x, $mp->{originy}, $tex);
            $x++;
        }
    }
    $tex->{composite} = $buf;
    for my $x (0 .. $tex->{width} - 1) {
        $tex->{col_ofs}[$x] = $x * $tex->{height} if $tex->{col_lump}[$x] < 0;
    }
    return;
}

sub _draw_column_in_cache {
    my ($self, $patch, $column, $cache, $x, $originy, $tex) = @_;
    while ($column < length($patch)) {
        my $topdelta = ord(substr($patch, $column, 1));
        last if $topdelta == 0xFF;
        my $length = ord(substr($patch, $column + 1, 1));
        my $source = $column + 3;
        my $pos = $originy + $topdelta;
        my $count = $length;
        if ($pos < 0) {
            $count += $pos;
            $source -= $pos;
            $pos = 0;
        }
        $count = $tex->{height} - $pos if $pos + $count > $tex->{height};
        my $dest = $x * $tex->{height} + $pos;
        for (my $i = 0; $i < $count; $i++) {
            substr($$cache, $dest + $i, 1) = substr($patch, $source + $i, 1);
        }
        $column += $length + 4;
    }
    return;
}

sub texture_num_for_name {
    my ($self, $name) = @_;
    $name = uc $name;
    $name =~ s/\s+$//;
    $name = substr($name, 0, 8);
    return 0 if $name eq '-' || $name eq '';
    return $self->{tex_index}{$name} // 0;
}

sub texture_height {
    my ($self, $texnum) = @_;
    return $self->{textures}[$texnum]{height} * FRACUNIT;
}

sub column_posts {
    my ($self, $texnum, $col) = @_;
    return () if $texnum < 0 || $texnum >= @{$self->{textures}};
    my $tex = $self->{textures}[$texnum];
    $col &= $tex->{widthmask};
    my $lump = $tex->{col_lump}[$col];
    my @posts;
    if ($lump >= 0) {
        my $patch = $self->{wad}->cache_lump_num($lump);
        my $column = $tex->{col_ofs}[$col];
        while ($column < length($patch)) {
            my $topdelta = ord(substr($patch, $column, 1));
            last if $topdelta == 0xFF;
            my $length = ord(substr($patch, $column + 1, 1));
            my $source = $column + 3;
            push @posts, [$topdelta, substr($patch, $source, $length)];
            $column += $length + 4;
        }
        return @posts;
    }
    $self->_generate_composite($tex);
    my $ofs = $tex->{col_ofs}[$col];
    my $colbytes = substr($tex->{composite}, $ofs, $tex->{height});
    push @posts, [0, $colbytes] if length($colbytes);
    return @posts;
}

sub get_column {
    my ($self, $texnum, $col) = @_;
    my $tex = $self->{textures}[$texnum];
    $col &= $tex->{widthmask};
    my $lump = $tex->{col_lump}[$col];
    if ($lump >= 0) {
        my $pdata = $self->{wad}->cache_lump_num($lump);
        return $self->_column_to_source($pdata, $tex->{col_ofs}[$col]);
    }
    $self->_generate_composite($tex);
    my $ofs = $tex->{col_ofs}[$col];
    return $self->_repeat_column(substr($tex->{composite}, $ofs, $tex->{height}));
}

sub _column_to_source {
    my ($self, $patch, $column) = @_;
    my $buf = "\0" x 128;
    while ($column < length($patch)) {
        my $topdelta = ord(substr($patch, $column, 1));
        last if $topdelta == 0xFF;
        my $length = ord(substr($patch, $column + 1, 1));
        my $source = $column + 3;
        for my $i (0 .. $length - 1) {
            my $y = $topdelta + $i;
            substr($buf, $y, 1) = substr($patch, $source + $i, 1) if $y >= 0 && $y < 128;
        }
        $column += $length + 4;
    }
    return $buf;
}

sub _repeat_column {
    my ($self, $colbytes) = @_;
    my $buf = "\0" x 128;
    return $buf if !length($colbytes);
    my $n = length($colbytes);
    for my $i (0 .. 127) {
        substr($buf, $i, 1) = substr($colbytes, $i % $n, 1);
    }
    return $buf;
}

sub flat_pixels {
    my ($self, $flatnum) = @_;
    my $data = $self->{wad}->cache_lump_num($self->flat_lump($flatnum));
    return substr($data, 0, 4096) if length($data) >= 4096;
    return $data . ("\0" x (4096 - length($data)));
}

1;
