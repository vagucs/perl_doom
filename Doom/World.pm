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
# Vertices, linhas, setores, segs e nos. Igual a doom/world.py.

package Doom::World;

use strict;
use warnings;

use Doom::Defs qw(
    FRACUNIT
    MAPLINEDEF_SIZE MAPNODE_SIZE MAPSECTOR_SIZE MAPSEG_SIZE
    MAPSIDEDEF_SIZE MAPSUBSECTOR_SIZE MAPTHING_SIZE MAPVERTEX_SIZE
    ML_TWOSIDED
    BOXLEFT BOXRIGHT BOXBOTTOM BOXTOP
    NF_SUBSECTOR
);
use Doom::Compat qw(as_i32);

sub _i16 {
    my $v = unpack('v', substr($_[0], $_[1], 2));
    return $v >= 32768 ? $v - 65536 : $v;
}

sub _u16 {
    return unpack('v', substr($_[0], $_[1], 2));
}

sub _name8 {
    my $raw = substr($_[0], $_[1], 8);
    $raw =~ s/\x00.*//s;
    $raw =~ s/\s+$//;
    return uc $raw;
}

sub new {
    my ($class) = @_;
    return bless {
        vertexes => [], sectors => [], sides => [], lines => [],
        segs => [], subsectors => [], nodes => [], things => [], mobjs => [],
        numnodes => 0,
        blockmap => [], blockmaplump => [], blocklinks => [],
        bmaporgx => 0, bmaporgy => 0,
        bmapwidth => 0, bmapheight => 0,
        validcount => 0,
        rejectmatrix => '',
    }, $class;
}

sub setup_level {
    my ($self, $wad, $res, $episode, $mapn) = @_;
    my $lumpname = sprintf('MAP%02d', $mapn);
    $lumpname = "E${episode}M$mapn" if $wad->check_num_for_name($lumpname) < 0;
    my $lumpnum = $wad->get_num_for_name($lumpname);
    $self->{name} = $lumpname;
    $self->_load_vertexes($wad->cache_lump_num($lumpnum + 4));
    $self->_load_sectors($wad->cache_lump_num($lumpnum + 8), $res);
    $self->_load_sides($wad->cache_lump_num($lumpnum + 3), $res);
    $self->_load_lines($wad->cache_lump_num($lumpnum + 2));
    $self->_load_segs($wad->cache_lump_num($lumpnum + 5));
    $self->_load_subsectors($wad->cache_lump_num($lumpnum + 6));
    $self->_load_nodes($wad->cache_lump_num($lumpnum + 7));
    $self->_load_things($wad->cache_lump_num($lumpnum + 1));
    $self->_load_blockmap($wad->cache_lump_num($lumpnum + 10));
    $self->{numnodes} = scalar @{$self->{nodes}};
    for my $ss (@{$self->{subsectors}}) {
        $ss->{sector} = $self->{segs}[$ss->{firstline}]{frontsector};
    }
    return;
}

sub _load_vertexes {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPVERTEX_SIZE);
    $self->{vertexes} = [];
    for my $i (0 .. $n - 1) {
        push @{$self->{vertexes}}, {
            x => _i16($data, $i * 4) * FRACUNIT,
            y => _i16($data, $i * 4 + 2) * FRACUNIT,
        };
    }
    return;
}

sub _load_sectors {
    my ($self, $data, $res) = @_;
    my $n = int(length($data) / MAPSECTOR_SIZE);
    $self->{sectors} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPSECTOR_SIZE;
        push @{$self->{sectors}}, {
            floorheight => _i16($data, $o) * FRACUNIT,
            ceilingheight => _i16($data, $o + 2) * FRACUNIT,
            floorpic => $res->flat_num_for_name(_name8($data, $o + 4)),
            ceilingpic => $res->flat_num_for_name(_name8($data, $o + 12)),
            lightlevel => _i16($data, $o + 20),
            special => _i16($data, $o + 22),
            tag => _i16($data, $o + 24),
            lines => [],
            i_sector => $i,
        };
    }
    return;
}

sub _load_sides {
    my ($self, $data, $res) = @_;
    my $n = int(length($data) / MAPSIDEDEF_SIZE);
    $self->{sides} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPSIDEDEF_SIZE;
        my $sec = _i16($data, $o + 28);
        $sec = 0 if $sec < 0 || $sec >= @{$self->{sectors}};
        push @{$self->{sides}}, {
            textureoffset => _i16($data, $o) * FRACUNIT,
            rowoffset => _i16($data, $o + 2) * FRACUNIT,
            toptexture => $res->texture_num_for_name(_name8($data, $o + 4)),
            bottomtexture => $res->texture_num_for_name(_name8($data, $o + 12)),
            midtexture => $res->texture_num_for_name(_name8($data, $o + 20)),
            sector => $self->{sectors}[$sec],
        };
    }
    return;
}

sub _load_lines {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPLINEDEF_SIZE);
    $self->{lines} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPLINEDEF_SIZE;
        my $v1 = $self->{vertexes}[_i16($data, $o)];
        my $v2 = $self->{vertexes}[_i16($data, $o + 2)];
        my $s0 = _i16($data, $o + 10);
        my $s1 = _i16($data, $o + 12);
        my $ln = {
            v1 => $v1, v2 => $v2,
            dx => $v2->{x} - $v1->{x},
            dy => $v2->{y} - $v1->{y},
            flags => _i16($data, $o + 4),
            special => _i16($data, $o + 6),
            tag => _i16($data, $o + 8),
            sidenum => [$s0, $s1],
            frontsector => $s0 >= 0 ? $self->{sides}[$s0]{sector} : undef,
            backsector => $s1 >= 0 ? $self->{sides}[$s1]{sector} : undef,
            sides => [
                $s0 >= 0 ? $self->{sides}[$s0] : undef,
                $s1 >= 0 ? $self->{sides}[$s1] : undef,
            ],
            i_line => $i,
            validcount => 0,
        };
        if ($v1->{x} < $v2->{x}) {
            $ln->{bbox}[BOXLEFT] = $v1->{x};
            $ln->{bbox}[BOXRIGHT] = $v2->{x};
        }
        else {
            $ln->{bbox}[BOXLEFT] = $v2->{x};
            $ln->{bbox}[BOXRIGHT] = $v1->{x};
        }
        if ($v1->{y} < $v2->{y}) {
            $ln->{bbox}[BOXBOTTOM] = $v1->{y};
            $ln->{bbox}[BOXTOP] = $v2->{y};
        }
        else {
            $ln->{bbox}[BOXBOTTOM] = $v2->{y};
            $ln->{bbox}[BOXTOP] = $v1->{y};
        }
        push @{$ln->{frontsector}{lines}}, $ln if $ln->{frontsector};
        if ($ln->{backsector} && $ln->{backsector} != $ln->{frontsector}) {
            push @{$ln->{backsector}{lines}}, $ln;
        }
        push @{$self->{lines}}, $ln;
    }
    return;
}

sub _load_segs {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPSEG_SIZE);
    $self->{segs} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPSEG_SIZE;
        my $ln = $self->{lines}[_i16($data, $o + 6)];
        my $side = _i16($data, $o + 8);
        my $sidedef = $ln->{sides}[$side] || $ln->{sides}[0];
        my $back;
        if ($ln->{flags} & ML_TWOSIDED) {
            $back = $ln->{sides}[$side ^ 1] ? $ln->{sides}[$side ^ 1]{sector} : undef;
        }
        push @{$self->{segs}}, {
            v1 => $self->{vertexes}[_i16($data, $o)],
            v2 => $self->{vertexes}[_i16($data, $o + 2)],
            angle => (_i16($data, $o + 4) << 16) & 0xFFFFFFFF,
            linedef => $ln,
            offset => _i16($data, $o + 10) * FRACUNIT,
            sidedef => $sidedef,
            frontsector => $sidedef ? $sidedef->{sector} : undef,
            backsector => $back,
        };
    }
    return;
}

sub _load_subsectors {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPSUBSECTOR_SIZE);
    $self->{subsectors} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPSUBSECTOR_SIZE;
        push @{$self->{subsectors}}, {
            numlines => _u16($data, $o),
            firstline => _u16($data, $o + 2),
            sector => undef,
        };
    }
    return;
}

sub _load_nodes {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPNODE_SIZE);
    $self->{nodes} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPNODE_SIZE;
        my @bbox;
        my $p = $o + 8;
        for (1 .. 2) {
            push @bbox, [
                _i16($data, $p) * FRACUNIT,
                _i16($data, $p + 2) * FRACUNIT,
                _i16($data, $p + 4) * FRACUNIT,
                _i16($data, $p + 6) * FRACUNIT,
            ];
            $p += 8;
        }
        push @{$self->{nodes}}, {
            x => _i16($data, $o) * FRACUNIT,
            y => _i16($data, $o + 2) * FRACUNIT,
            dx => _i16($data, $o + 4) * FRACUNIT,
            dy => _i16($data, $o + 6) * FRACUNIT,
            bbox => \@bbox,
            children => [_u16($data, $p), _u16($data, $p + 2)],
        };
    }
    return;
}

sub _load_things {
    my ($self, $data) = @_;
    my $n = int(length($data) / MAPTHING_SIZE);
    $self->{things} = [];
    for my $i (0 .. $n - 1) {
        my $o = $i * MAPTHING_SIZE;
        push @{$self->{things}}, {
            x => _i16($data, $o),
            y => _i16($data, $o + 2),
            angle => _i16($data, $o + 4),
            type => _i16($data, $o + 6),
            options => _i16($data, $o + 8),
        };
    }
    return;
}

sub _load_blockmap {
    my ($self, $data) = @_;
    my $n = int(length($data) / 2);
    my @lump;
    for my $i (0 .. $n - 1) {
        push @lump, unpack('v', substr($data, $i * 2, 2));
    }
    $self->{blockmaplump} = \@lump;
    $self->{blockmap} = [];
    $self->{blocklinks} = [];
    return if $n < 4;
    $self->{bmaporgx} = _i16($data, 0) * FRACUNIT;
    $self->{bmaporgy} = _i16($data, 2) * FRACUNIT;
    $self->{bmapwidth} = _i16($data, 4);
    $self->{bmapheight} = _i16($data, 6);
    my $count = $self->{bmapwidth} * $self->{bmapheight};
    return if $count <= 0;
    $self->{blockmap} = [@lump[4 .. 4 + $count - 1]];
    $self->{blocklinks} = [(undef) x $count];
    return;
}

sub player_start {
    my ($self) = @_;
    for my $t (@{$self->{things}}) {
        return $t if $t->{type} == 1;
    }
    return $self->{things}[0];
}

sub point_on_side {
    my ($x, $y, $node) = @_;
    my $dx = as_i32($x - $node->{x});
    my $dy = as_i32($y - $node->{y});
    my $left = as_i32($node->{dy} >> 16) * $dx;
    my $right = $dy * as_i32($node->{dx} >> 16);
    return $right >= $left ? 1 : 0;
}

sub point_in_subsector {
    my ($self, $x, $y) = @_;
    my $nodenum = $self->{numnodes} - 1;
    return $self->{subsectors}[0] if $nodenum < 0;
    while (!($nodenum & NF_SUBSECTOR)) {
        my $node = $self->{nodes}[$nodenum];
        $nodenum = $node->{children}[point_on_side($x, $y, $node)];
    }
    return $self->{subsectors}[$nodenum & ~NF_SUBSECTOR];
}

1;
