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
# Vista: BSP, paredes, piso, teto e ceu. Igual a doom/render.py.

package Doom::Render;

use strict;
use warnings;

use Doom::Compat qw(abs_fixed as_i32 as_u32 fixed_div fixed_mul shar ushr);
use Doom::Defs qw(
    ANGLETOFINESHIFT ANG90 ANG180 DBITS FIELDOFVIEW FINEANGLES FINEMASK
    FRACBITS FRACUNIT
    LIGHTLEVELS LIGHTSCALESHIFT LIGHTZSHIFT MAXLIGHTSCALE MAXLIGHTZ
    ML_DONTPEGBOTTOM ML_DONTPEGTOP ML_MAPPED
    NF_SUBSECTOR NUMCOLORMAPS
    SBARHEIGHT SCREENHEIGHT SCREENWIDTH
    SIL_BOTH SIL_BOTTOM SIL_NONE SIL_TOP
);
use Doom::Tables qw(init_tables fine_sin fine_cos slope_div);
use Doom::Profile;

use constant HEIGHTBITS => 12;
use constant HEIGHTUNIT => 4096;
use constant ANGLETOSKYSHIFT => 22;
use constant SHRT_MAX => 0x7FFF;

sub new {
    my ($class, $res) = @_;
    init_tables();
    my $self = bless { res => $res }, $class;
    $self->set_view_size(10, 0);
    return $self;
}

sub set_view_size {
    my ($self, $blocks, $detail) = @_;
    $blocks = 3 if $blocks < 3;
    $blocks = 11 if $blocks > 11;
    $detail = $detail ? 1 : 0;
    $self->{screenblocks} = $blocks;
    $self->{detailshift} = $detail;
    my ($scaled, $viewheight);
    if ($blocks == 11) {
        $scaled = SCREENWIDTH;
        $viewheight = SCREENHEIGHT;
    }
    else {
        $scaled = $blocks * 32;
        $viewheight = ($blocks * 168 / 10) & ~7;
    }
    $self->{scaledviewwidth} = $scaled;
    $self->{viewwidth} = $scaled >> $detail;
    $self->{viewheight} = $viewheight;
    $self->{centerx} = int($self->{viewwidth} / 2);
    $self->{centery} = int($self->{viewheight} / 2);
    $self->{centerxfrac} = $self->{centerx} << FRACBITS;
    $self->{centeryfrac} = $self->{centery} << FRACBITS;
    $self->{projection} = $self->{centerxfrac};
    $self->{viewwindowx} = (SCREENWIDTH - $scaled) >> 1;
    if ($scaled == SCREENWIDTH) {
        $self->{viewwindowy} = 0;
    }
    else {
        $self->{viewwindowy} = (SCREENHEIGHT - SBARHEIGHT - $viewheight) >> 1;
    }
    $self->{ylookup} = [map { ($_ + $self->{viewwindowy}) * SCREENWIDTH } 0 .. SCREENHEIGHT - 1];
    $self->{columnofs} = [map { $self->{viewwindowx} + $_ } 0 .. SCREENWIDTH - 1];
    $self->{ceilingclip} = [(0) x $self->{viewwidth}];
    $self->{floorclip} = [(0) x $self->{viewwidth}];
    $self->{pspritescale} = int(FRACUNIT * $self->{viewwidth} / SCREENWIDTH) || FRACUNIT;
    $self->{pspriteiscale} = int(FRACUNIT * SCREENWIDTH / ($self->{viewwidth} || 1));
    $self->{solidsegs} = [map { { first => 0, last => 0 } } 1 .. 64];
    $self->{fb} = "\0" x (SCREENWIDTH * SCREENHEIGHT);
    $self->_init_mapping;
    $self->_init_slopes;
    $self->_init_lights;
    $self->{lookapplied} = -999;
    return;
}

sub _init_mapping {
    my ($self) = @_;
    my $focallength = fixed_div(
        $self->{centerxfrac},
        $Doom::Tables::FINETANGENT[int(FINEANGLES / 4) + int(FIELDOFVIEW / 2)],
    );
    my $half = int(FINEANGLES / 2);
    $self->{viewangletox} = [];
    for my $i (0 .. $half - 1) {
        my $ft = $Doom::Tables::FINETANGENT[$i];
        my $t;
        if ($ft > FRACUNIT * 2) {
            $t = -1;
        }
        elsif ($ft < -FRACUNIT * 2) {
            $t = $self->{viewwidth} + 1;
        }
        else {
            $t = shar($self->{centerxfrac} - fixed_mul($ft, $focallength) + FRACUNIT - 1, FRACBITS);
            $t = -1 if $t < -1;
            $t = $self->{viewwidth} + 1 if $t > $self->{viewwidth} + 1;
        }
        $self->{viewangletox}[$i] = $t;
    }
    $self->{xtoviewangle} = [];
    for my $x (0 .. $self->{viewwidth}) {
        my $i = 0;
        $i++ while $i < $half && $self->{viewangletox}[$i] > $x;
        $self->{xtoviewangle}[$x] = as_u32(($i << ANGLETOFINESHIFT) - ANG90);
    }
    for my $i (0 .. $half - 1) {
        if ($self->{viewangletox}[$i] == -1) {
            $self->{viewangletox}[$i] = 0;
        }
        elsif ($self->{viewangletox}[$i] == $self->{viewwidth} + 1) {
            $self->{viewangletox}[$i] = $self->{viewwidth};
        }
    }
    $self->{clipangle} = $self->{xtoviewangle}[0];
    return;
}

sub _init_lights {
    my ($self) = @_;
    $self->{scalelight} = [];
    $self->{zlight} = [];
    for my $i (0 .. LIGHTLEVELS - 1) {
        my $startmap = int(((LIGHTLEVELS - 1 - $i) * 2) * NUMCOLORMAPS / LIGHTLEVELS);
        for my $j (0 .. MAXLIGHTZ - 1) {
            my $scale = fixed_div((int(SCREENWIDTH / 2) * FRACUNIT), ($j + 1) << LIGHTZSHIFT) >> LIGHTSCALESHIFT;
            my $level = $startmap - int($scale / 2);
            $level = 0 if $level < 0;
            $level = NUMCOLORMAPS - 1 if $level > NUMCOLORMAPS - 1;
            $self->{zlight}[$i][$j] = $level;
        }
        for my $j (0 .. MAXLIGHTSCALE - 1) {
            my $vw = $self->{viewwidth} << $self->{detailshift};
            $vw = 1 if $vw < 1;
            my $level = $startmap - int($j * SCREENWIDTH / $vw / 2);
            $level = 0 if $level < 0;
            $level = NUMCOLORMAPS - 1 if $level > NUMCOLORMAPS - 1;
            $self->{scalelight}[$i][$j] = $level;
        }
    }
    return;
}

sub _init_slopes {
    my ($self) = @_;
    $self->{yslope} = [];
    for my $i (0 .. $self->{viewheight} - 1) {
        my $dy = abs((($i - $self->{centery}) << FRACBITS) + int(FRACUNIT / 2));
        $dy = 1 if $dy < 1;
        $self->{yslope}[$i] = fixed_div((int(($self->{viewwidth} << $self->{detailshift}) / 2)) * FRACUNIT, $dy);
    }
    $self->{distscale} = [];
    for my $i (0 .. $self->{viewwidth} - 1) {
        my $cosadj = abs_fixed(fine_cos($self->{xtoviewangle}[$i]));
        $cosadj = 1 if $cosadj < 1;
        $self->{distscale}[$i] = fixed_div(FRACUNIT, $cosadj);
    }
    return;
}

sub point_to_angle {
    my ($self, $x, $y) = @_;
    $x = as_i32($x - $self->{viewx});
    $y = as_i32($y - $self->{viewy});
    return 0 if $x == 0 && $y == 0;
    if ($x >= 0) {
        if ($y >= 0) {
            return $Doom::Tables::TANTOANGLE[slope_div($y, $x)] if $x > $y;
            return as_u32(ANG90 - 1 - $Doom::Tables::TANTOANGLE[slope_div($x, $y)]);
        }
        $y = -$y;
        return as_u32(-$Doom::Tables::TANTOANGLE[slope_div($y, $x)]) if $x > $y;
        return as_u32(0xC0000000 + $Doom::Tables::TANTOANGLE[slope_div($x, $y)]);
    }
    $x = -$x;
    if ($y >= 0) {
        return as_u32(ANG180 - 1 - $Doom::Tables::TANTOANGLE[slope_div($y, $x)]) if $x > $y;
        return as_u32(ANG90 + $Doom::Tables::TANTOANGLE[slope_div($x, $y)]);
    }
    $y = -$y;
    return as_u32(ANG180 + $Doom::Tables::TANTOANGLE[slope_div($y, $x)]) if $x > $y;
    return as_u32(0xC0000000 - 1 - $Doom::Tables::TANTOANGLE[slope_div($x, $y)]);
}

sub point_on_side {
    my ($self, $x, $y, $node) = @_;
    my $dx = as_i32($x - $node->{x});
    my $dy = as_i32($y - $node->{y});
    my $left = as_i32($node->{dy} >> 16) * $dx;
    my $right = $dy * as_i32($node->{dx} >> 16);
    return $right >= $left ? 1 : 0;
}

sub scale_from_global_angle {
    my ($self, $visangle) = @_;
    my $anglea = as_u32(ANG90 + as_u32($visangle - $self->{viewangle}));
    my $angleb = as_u32(ANG90 + as_u32($visangle - $self->{rw_normalangle}));
    my $sinea = $Doom::Tables::FINESINE[($anglea >> ANGLETOFINESHIFT) & FINEMASK];
    my $sineb = $Doom::Tables::FINESINE[($angleb >> ANGLETOFINESHIFT) & FINEMASK];
    my $num = fixed_mul($self->{projection}, $sineb) << $self->{detailshift};
    my $den = fixed_mul($self->{rw_distance}, $sinea);
    my $scale;
    if ($den > ($num >> 16) && $den) {
        $scale = fixed_div($num, $den);
        $scale = 64 * FRACUNIT if $scale > 64 * FRACUNIT;
        $scale = 256 if $scale < 256;
    }
    else {
        $scale = 64 * FRACUNIT;
    }
    return $scale;
}

sub setup_frame {
    my ($self, $x, $y, $z, $angle) = @_;
    $self->{viewx} = $x;
    $self->{viewy} = $y;
    $self->{viewz} = $z;
    my $base = int($self->{viewheight} / 2);
    my $look = $self->{look} || 0;
    my $cap = $base > 1 ? $base - 1 : 0;
    $look = $cap if $look > $cap;
    $look = -$cap if $look < -$cap;
    if ($look != ($self->{lookapplied} || 0)) {
        $self->{centery} = $base + $look;
        $self->{centeryfrac} = $self->{centery} << FRACBITS;
        $self->_init_slopes;
        $self->{lookapplied} = $look;
    }
    $self->{viewangle} = as_u32($angle);
    $self->{viewsin} = fine_sin($self->{viewangle});
    $self->{viewcos} = fine_cos($self->{viewangle});
    $self->{extralight} = 0;
    $self->{fixedcolormap} = undef;
    my $ang = ushr(as_u32($self->{viewangle} - ANG90), ANGLETOFINESHIFT) & FINEMASK;
    my $cx = $self->{centerxfrac} || 1;
    $self->{basexscale} = fixed_div($Doom::Tables::FINESINE[($ang + int(FINEANGLES / 4)) & FINEMASK], $cx);
    $self->{baseyscale} = -fixed_div($Doom::Tables::FINESINE[$ang], $cx);
    return;
}

sub render {
    my $pt = $Doom::Profile::ON ? Doom::Profile::now() : 0;
    my ($self, $world) = @_;
    $self->{fb} = "\0" x (SCREENWIDTH * SCREENHEIGHT);
    $self->{visplanes} = [];
    $self->{drawsegs} = [];
    $self->_clear_clip;
    if (@{$world->{nodes}}) {
        $self->_render_bsp_node($world, $world->{numnodes} - 1);
    }
    else {
        $self->_subsector($world, 0);
    }
    $self->_draw_planes;
    Doom::Profile::add('render', Doom::Profile::now() - $pt) if $pt;
    return $self->{fb};
}

sub _clear_clip {
    my ($self) = @_;
    $self->{solidsegs}[0] = { first => -0x7FFFFFFF, last => -1 };
    $self->{solidsegs}[1] = { first => $self->{viewwidth}, last => 0x7FFFFFFF };
    $self->{newend} = 2;
    for my $i (0 .. $self->{viewwidth} - 1) {
        $self->{floorclip}[$i] = $self->{viewheight};
        $self->{ceilingclip}[$i] = -1;
    }
    return;
}

sub _find_plane {
    my ($self, $height, $picnum, $lightlevel) = @_;
    if ($picnum == $self->{res}{skyflatnum}) {
        $height = 0;
        $lightlevel = 0;
    }
    for my $p (@{$self->{visplanes}}) {
        if ($p->{height} == $height && $p->{picnum} == $picnum && $p->{lightlevel} == $lightlevel) {
            return $p;
        }
    }
    my $p = {
        height => $height, picnum => $picnum, lightlevel => $lightlevel,
        minx => $self->{viewwidth}, maxx => -1,
        top => [(0xFF) x SCREENWIDTH],
        bottom => [(0) x SCREENWIDTH],
    };
    push @{$self->{visplanes}}, $p;
    return $p;
}

sub _check_plane {
    my ($self, $pl, $start, $stop) = @_;
    return $self->_find_plane(0, 0, 0) if !$pl;
    my ($intrl, $unionl, $intrh, $unionh);
    if ($start < $pl->{minx}) {
        ($intrl, $unionl) = ($pl->{minx}, $start);
    }
    else {
        ($unionl, $intrl) = ($pl->{minx}, $start);
    }
    if ($stop > $pl->{maxx}) {
        ($intrh, $unionh) = ($pl->{maxx}, $stop);
    }
    else {
        ($unionh, $intrh) = ($pl->{maxx}, $stop);
    }
    my $x = $intrl;
    while ($x <= $intrh) {
        last if $x >= 0 && $x < SCREENWIDTH && $pl->{top}[$x] != 0xFF;
        $x++;
    }
    if ($x > $intrh) {
        $pl->{minx} = $unionl;
        $pl->{maxx} = $unionh;
        return $pl;
    }
    return $self->_dup_plane($pl, $start, $stop);
}

sub _dup_plane {
    my ($self, $src, $start, $stop) = @_;
    my $p = {
        height => $src->{height}, picnum => $src->{picnum}, lightlevel => $src->{lightlevel},
        minx => $start, maxx => $stop,
        top => [(0xFF) x SCREENWIDTH],
        bottom => [(0) x SCREENWIDTH],
    };
    push @{$self->{visplanes}}, $p;
    return $p;
}

sub _render_bsp_node {
    my ($self, $world, $bspnum) = @_;
    if (($bspnum & NF_SUBSECTOR) || $bspnum < 0) {
        my $num = $bspnum == -1 ? 0 : ($bspnum & ~NF_SUBSECTOR);
        $self->_subsector($world, $num);
        return;
    }
    my $node = $world->{nodes}[$bspnum];
    my $side = $self->point_on_side($self->{viewx}, $self->{viewy}, $node);
    $self->_render_bsp_node($world, $node->{children}[$side]);
    $self->_render_bsp_node($world, $node->{children}[$side ^ 1]);
    return;
}

sub _subsector {
    my ($self, $world, $num) = @_;
    my $sub = $world->{subsectors}[$num];
    $self->{frontsector} = $sub->{sector};
    my $light = ($self->{frontsector}{lightlevel} >> 4) + $self->{extralight};
    $light = 0 if $light < 0;
    $light = LIGHTLEVELS - 1 if $light > LIGHTLEVELS - 1;
    $self->{walllights} = $self->{scalelight}[$light];
    $self->{floorplane} = $self->_find_plane(
        $self->{frontsector}{floorheight}, $self->{frontsector}{floorpic}, $self->{frontsector}{lightlevel},
    );
    $self->{ceilingplane} = $self->_find_plane(
        $self->{frontsector}{ceilingheight}, $self->{frontsector}{ceilingpic}, $self->{frontsector}{lightlevel},
    );
    my $line = $sub->{firstline};
    for (1 .. $sub->{numlines}) {
        $self->_add_line($world->{segs}[$line]);
        $line++;
    }
    return;
}

sub _add_line {
    my ($self, $line) = @_;
    $self->{curline} = $line;
    my $angle1 = $self->point_to_angle($line->{v1}{x}, $line->{v1}{y});
    my $angle2 = $self->point_to_angle($line->{v2}{x}, $line->{v2}{y});
    my $span = as_u32($angle1 - $angle2);
    return if $span >= ANG180;
    $self->{rw_angle1} = $angle1;
    $angle1 = as_u32($angle1 - $self->{viewangle});
    $angle2 = as_u32($angle2 - $self->{viewangle});
    my $tspan = as_u32($angle1 + $self->{clipangle});
    if ($tspan > as_u32(2 * $self->{clipangle})) {
        $tspan = as_u32($tspan - 2 * $self->{clipangle});
        return if $tspan >= $span;
        $angle1 = $self->{clipangle};
    }
    $tspan = as_u32($self->{clipangle} - $angle2);
    if ($tspan > as_u32(2 * $self->{clipangle})) {
        $tspan = as_u32($tspan - 2 * $self->{clipangle});
        return if $tspan >= $span;
        $angle2 = as_u32(-$self->{clipangle});
    }
    my $mask = int(FINEANGLES / 2) - 1;
    my $x1 = $self->{viewangletox}[ushr(as_u32($angle1 + ANG90), ANGLETOFINESHIFT) & $mask];
    my $x2 = $self->{viewangletox}[ushr(as_u32($angle2 + ANG90), ANGLETOFINESHIFT) & $mask];
    return if $x1 == $x2;
    $self->{backsector} = $line->{backsector};
    if (!$self->{backsector}) {
        $self->_clip_solid($x1, $x2 - 1);
        return;
    }
    if ($self->{backsector}{ceilingheight} <= $self->{frontsector}{floorheight}
        || $self->{backsector}{floorheight} >= $self->{frontsector}{ceilingheight}) {
        $self->_clip_solid($x1, $x2 - 1);
        return;
    }
    $self->_clip_pass($x1, $x2 - 1);
    return;
}

sub _clip_solid {
    my ($self, $first, $last) = @_;
    return if $first > $last;
    my $start = 0;
    $start++ while $start < $self->{newend} && $self->{solidsegs}[$start]{last} < $first - 1;
    if ($start >= $self->{newend}) {
        $self->_store_wall_range($first, $last);
        return;
    }
    if ($first < $self->{solidsegs}[$start]{first}) {
        if ($last < $self->{solidsegs}[$start]{first} - 1) {
            $self->_store_wall_range($first, $last);
            splice @{$self->{solidsegs}}, $start, 0, { first => $first, last => $last };
            $self->{newend}++;
            push @{$self->{solidsegs}}, { first => 0, last => 0 } if $self->{newend} > @{$self->{solidsegs}};
            return;
        }
        $self->_store_wall_range($first, $self->{solidsegs}[$start]{first} - 1);
        $self->{solidsegs}[$start]{first} = $first;
    }
    return if $last <= $self->{solidsegs}[$start]{last};
    my $nexti = $start;
    while ($nexti + 1 < $self->{newend} && $last >= $self->{solidsegs}[$nexti + 1]{first} - 1) {
        $self->_store_wall_range($self->{solidsegs}[$nexti]{last} + 1, $self->{solidsegs}[$nexti + 1]{first} - 1);
        $nexti++;
        if ($last <= $self->{solidsegs}[$nexti]{last}) {
            $self->{solidsegs}[$start]{last} = $self->{solidsegs}[$nexti]{last};
            $self->_crunch_solid($start, $nexti);
            return;
        }
    }
    $self->_store_wall_range($self->{solidsegs}[$nexti]{last} + 1, $last);
    $self->{solidsegs}[$start]{last} = $last;
    $self->_crunch_solid($start, $nexti);
    return;
}

sub _crunch_solid {
    my ($self, $start, $nexti) = @_;
    return if $nexti == $start;
    my @tail = @{$self->{solidsegs}}[$nexti + 1 .. $self->{newend} - 1];
    splice @{$self->{solidsegs}}, $start + 1, $self->{newend} - ($start + 1), @tail;
    $self->{newend} = $start + 1 + @tail;
    push @{$self->{solidsegs}}, { first => 0, last => 0 } while @{$self->{solidsegs}} < 64;
    return;
}

sub _clip_pass {
    my ($self, $first, $last) = @_;
    return if $first > $last;
    my $start = 0;
    $start++ while $start < $self->{newend} && $self->{solidsegs}[$start]{last} < $first - 1;
    if ($start >= $self->{newend}) {
        $self->_store_wall_range($first, $last);
        return;
    }
    if ($first < $self->{solidsegs}[$start]{first}) {
        if ($last < $self->{solidsegs}[$start]{first} - 1) {
            $self->_store_wall_range($first, $last);
            return;
        }
        $self->_store_wall_range($first, $self->{solidsegs}[$start]{first} - 1);
    }
    return if $last <= $self->{solidsegs}[$start]{last};
    my $nexti = $start;
    while ($nexti + 1 < $self->{newend} && $last >= $self->{solidsegs}[$nexti + 1]{first} - 1) {
        $self->_store_wall_range($self->{solidsegs}[$nexti]{last} + 1, $self->{solidsegs}[$nexti + 1]{first} - 1);
        $nexti++;
        return if $last <= $self->{solidsegs}[$nexti]{last};
    }
    $self->_store_wall_range($self->{solidsegs}[$nexti]{last} + 1, $last);
    return;
}

sub _store_wall_range {
    my ($self, $start, $stop) = @_;
    return if $start > $stop;
    my $line = $self->{curline};
    my $linedef = $line->{linedef};
    my $sidedef = $line->{sidedef};
    $linedef->{flags} |= ML_MAPPED;
    $self->{rw_normalangle} = as_u32($line->{angle} + ANG90);
    my $offsetangle = as_u32($self->{rw_normalangle} - $self->{rw_angle1});
    $offsetangle = as_u32(-$offsetangle) if $offsetangle > ANG180;
    $offsetangle = ANG90 if $offsetangle > ANG90;
    my $distangle = as_u32(ANG90 - $offsetangle);
    my $hyp = $self->_point_to_dist($line->{v1}{x}, $line->{v1}{y});
    $self->{rw_distance} = fixed_mul($hyp, $Doom::Tables::FINESINE[($distangle >> ANGLETOFINESHIFT) & FINEMASK]);
    $self->{rw_x} = $start;
    $self->{rw_start} = $start;
    $self->{rw_stopx} = $stop + 1;
    $self->{rw_scale} = $self->scale_from_global_angle(as_u32($self->{viewangle} + $self->{xtoviewangle}[$start]));
    if ($stop > $start) {
        my $scale2 = $self->scale_from_global_angle(as_u32($self->{viewangle} + $self->{xtoviewangle}[$stop]));
        $self->{rw_scalestep} = int(($scale2 - $self->{rw_scale}) / ($stop - $start));
    }
    else {
        $self->{rw_scalestep} = 0;
    }
    $self->{worldtop} = $self->{frontsector}{ceilingheight} - $self->{viewz};
    $self->{worldbottom} = $self->{frontsector}{floorheight} - $self->{viewz};
    $self->{midtexture} = $self->{toptexture} = $self->{bottomtexture} = 0;
    $self->{maskedtexture} = 0;
    $self->{maskedtexturecol} = undef;
    $self->{segtextured} = 0;
    if (!$self->{backsector}) {
        $self->{midtexture} = $sidedef->{midtexture};
        $self->{markfloor} = $self->{markceiling} = 1;
        if ($linedef->{flags} & ML_DONTPEGBOTTOM) {
            my $vtop = $self->{frontsector}{floorheight} + $self->{res}->texture_height($self->{midtexture});
            $self->{rw_midtexturemid} = $vtop - $self->{viewz};
        }
        else {
            $self->{rw_midtexturemid} = $self->{worldtop};
        }
        $self->{rw_midtexturemid} += $sidedef->{rowoffset};
    }
    else {
        $self->{worldhigh} = $self->{backsector}{ceilingheight} - $self->{viewz};
        $self->{worldlow} = $self->{backsector}{floorheight} - $self->{viewz};
        if ($self->{frontsector}{ceilingpic} == $self->{res}{skyflatnum}
            && $self->{backsector}{ceilingpic} == $self->{res}{skyflatnum}) {
            $self->{worldtop} = $self->{worldhigh};
        }
        $self->{markfloor} = (
            $self->{worldlow} != $self->{worldbottom}
            || $self->{backsector}{floorpic} != $self->{frontsector}{floorpic}
            || $self->{backsector}{lightlevel} != $self->{frontsector}{lightlevel}
        ) ? 1 : 0;
        $self->{markceiling} = (
            $self->{worldhigh} != $self->{worldtop}
            || $self->{backsector}{ceilingpic} != $self->{frontsector}{ceilingpic}
            || $self->{backsector}{lightlevel} != $self->{frontsector}{lightlevel}
        ) ? 1 : 0;
        if ($self->{backsector}{ceilingheight} <= $self->{frontsector}{floorheight}
            || $self->{backsector}{floorheight} >= $self->{frontsector}{ceilingheight}) {
            $self->{markceiling} = $self->{markfloor} = 1;
        }
        if ($self->{worldhigh} < $self->{worldtop}) {
            $self->{toptexture} = $sidedef->{toptexture};
            if ($linedef->{flags} & ML_DONTPEGTOP) {
                $self->{rw_toptexturemid} = $self->{worldtop};
            }
            else {
                my $vtop = $self->{backsector}{ceilingheight} + $self->{res}->texture_height($self->{toptexture} || 0);
                $self->{rw_toptexturemid} = $vtop - $self->{viewz};
            }
        }
        if ($self->{worldlow} > $self->{worldbottom}) {
            $self->{bottomtexture} = $sidedef->{bottomtexture};
            if ($linedef->{flags} & ML_DONTPEGBOTTOM) {
                $self->{rw_bottomtexturemid} = $self->{worldtop};
            }
            else {
                $self->{rw_bottomtexturemid} = $self->{worldlow};
            }
        }
        $self->{rw_toptexturemid} += $sidedef->{rowoffset};
        $self->{rw_bottomtexturemid} += $sidedef->{rowoffset};
        if ($sidedef->{midtexture}) {
            $self->{maskedtexture} = 1;
            $self->{maskedtexturecol} = [(SHRT_MAX) x ($stop - $start + 1)];
        }
    }
    $self->{segtextured} = ($self->{midtexture} || $self->{toptexture} || $self->{bottomtexture} || $self->{maskedtexture}) ? 1 : 0;
    if ($self->{segtextured}) {
        $offsetangle = as_u32($self->{rw_normalangle} - $self->{rw_angle1});
        $offsetangle = as_u32(-$offsetangle) if $offsetangle > ANG180;
        $self->{rw_offset} = fixed_mul($hyp, $Doom::Tables::FINESINE[($offsetangle >> ANGLETOFINESHIFT) & FINEMASK]);
        $self->{rw_offset} = -$self->{rw_offset} if as_u32($self->{rw_normalangle} - $self->{rw_angle1}) < ANG180;
        $self->{rw_offset} += $sidedef->{textureoffset} + $line->{offset};
        $self->{rw_centerangle} = as_u32(ANG90 + $self->{viewangle} - $self->{rw_normalangle});
    }
    $self->{markfloor} = 0 if $self->{frontsector}{floorheight} >= $self->{viewz};
    if ($self->{frontsector}{ceilingheight} <= $self->{viewz}
        && $self->{frontsector}{ceilingpic} != $self->{res}{skyflatnum}) {
        $self->{markceiling} = 0;
    }
    $self->{ceilingplane} = $self->_check_plane($self->{ceilingplane}, $start, $stop) if $self->{markceiling};
    $self->{floorplane} = $self->_check_plane($self->{floorplane}, $start, $stop) if $self->{markfloor};
    $self->{worldtop} = shar($self->{worldtop}, 4);
    $self->{worldbottom} = shar($self->{worldbottom}, 4);
    $self->{topstep} = -fixed_mul($self->{rw_scalestep}, $self->{worldtop});
    $self->{topfrac} = ($self->{centeryfrac} >> 4) - fixed_mul($self->{worldtop}, $self->{rw_scale});
    $self->{bottomstep} = -fixed_mul($self->{rw_scalestep}, $self->{worldbottom});
    $self->{bottomfrac} = ($self->{centeryfrac} >> 4) - fixed_mul($self->{worldbottom}, $self->{rw_scale});
    if ($self->{backsector}) {
        $self->{worldhigh} = shar($self->{worldhigh}, 4);
        $self->{worldlow} = shar($self->{worldlow}, 4);
        if ($self->{worldhigh} < $self->{worldtop}) {
            $self->{pixhigh} = ($self->{centeryfrac} >> 4) - fixed_mul($self->{worldhigh}, $self->{rw_scale});
            $self->{pixhighstep} = -fixed_mul($self->{rw_scalestep}, $self->{worldhigh});
        }
        if ($self->{worldlow} > $self->{worldbottom}) {
            $self->{pixlow} = ($self->{centeryfrac} >> 4) - fixed_mul($self->{worldlow}, $self->{rw_scale});
            $self->{pixlowstep} = -fixed_mul($self->{rw_scalestep}, $self->{worldlow});
        }
    }
    my $scale1 = $self->{rw_scale};
    $self->_render_seg_loop;
    $self->_push_drawseg($start, $stop, $scale1);
    return;
}

sub _push_drawseg {
    my ($self, $start, $stop, $scale1) = @_;
    my $ds = {
        x1 => $start, x2 => $stop, scale1 => $scale1,
        scale2 => $scale1 + $self->{rw_scalestep} * ($stop - $start > 0 ? $stop - $start : 0),
        curline => $self->{curline},
        scalestep => $self->{rw_scalestep},
        maskedtexturecol => $self->{maskedtexturecol},
        silhouette => SIL_NONE,
        bsilheight => 0, tsilheight => 0,
        sprtopclip => [],
        sprbottomclip => [],
    };
    my $imax = 0x7FFFFFFF;
    my $imin = -0x7FFFFFFF;
    if (!$self->{backsector}) {
        $ds->{silhouette} = SIL_BOTH;
        $ds->{bsilheight} = $imax;
        $ds->{tsilheight} = $imin;
        my $width = $stop - $start + 1;
        $ds->{sprtopclip} = [($self->{viewheight}) x $width];
        $ds->{sprbottomclip} = [(-1) x $width];
    }
    else {
        my $front = $self->{frontsector};
        my $back = $self->{backsector};
        if ($front->{floorheight} > $back->{floorheight}) {
            $ds->{silhouette} = SIL_BOTTOM;
            $ds->{bsilheight} = $front->{floorheight};
        }
        elsif ($back->{floorheight} > $self->{viewz}) {
            $ds->{silhouette} = SIL_BOTTOM;
            $ds->{bsilheight} = $imax;
        }
        if ($front->{ceilingheight} < $back->{ceilingheight}) {
            $ds->{silhouette} |= SIL_TOP;
            $ds->{tsilheight} = $front->{ceilingheight};
        }
        elsif ($back->{ceilingheight} < $self->{viewz}) {
            $ds->{silhouette} |= SIL_TOP;
            $ds->{tsilheight} = $imin;
        }
        if ($back->{ceilingheight} <= $front->{floorheight}) {
            $ds->{silhouette} |= SIL_BOTTOM;
            $ds->{bsilheight} = $imax;
        }
        if ($back->{floorheight} >= $front->{ceilingheight}) {
            $ds->{silhouette} |= SIL_TOP;
            $ds->{tsilheight} = $imin;
        }
        $ds->{sprtopclip} = [ @{$self->{ceilingclip}}[$start .. $stop] ];
        $ds->{sprbottomclip} = [ @{$self->{floorclip}}[$start .. $stop] ];
        if ($self->{maskedtexture}) {
            if (!($ds->{silhouette} & SIL_TOP)) {
                $ds->{silhouette} |= SIL_TOP;
                $ds->{tsilheight} = $imin;
            }
            if (!($ds->{silhouette} & SIL_BOTTOM)) {
                $ds->{silhouette} |= SIL_BOTTOM;
                $ds->{bsilheight} = $imax;
            }
        }
        if ($back->{ceilingheight} <= $back->{floorheight}) {
            my $width = $stop - $start + 1;
            $ds->{silhouette} = SIL_BOTH;
            $ds->{bsilheight} = $imax;
            $ds->{tsilheight} = $imin;
            $ds->{sprtopclip} = [($self->{viewheight}) x $width];
            $ds->{sprbottomclip} = [(-1) x $width];
        }
    }
    push @{$self->{drawsegs}}, $ds;
    return;
}

sub _point_to_dist {
    my ($self, $x, $y) = @_;
    my $dx = abs_fixed($x - $self->{viewx});
    my $dy = abs_fixed($y - $self->{viewy});
    ($dx, $dy) = ($dy, $dx) if $dy > $dx;
    return 0 if $dx == 0;
    my $frac = fixed_div($dy, $dx);
    my $idx = $frac >> DBITS;
    $idx = 2048 if $idx > 2048;
    my $ang = ($Doom::Tables::TANTOANGLE[$idx] + ANG90) >> ANGLETOFINESHIFT;
    return fixed_div($dx, $Doom::Tables::FINESINE[$ang & FINEMASK]);
}

sub _render_seg_loop {
    my ($self) = @_;
    my $texturecolumn = 0;
    while ($self->{rw_x} < $self->{rw_stopx}) {
        my $x = $self->{rw_x};
        my $yl = shar($self->{topfrac} + HEIGHTUNIT - 1, HEIGHTBITS);
        $yl = $self->{ceilingclip}[$x] + 1 if $yl < $self->{ceilingclip}[$x] + 1;
        if ($self->{markceiling} && $self->{ceilingplane}) {
            my $top = $self->{ceilingclip}[$x] + 1;
            my $bottom = $yl - 1;
            $bottom = $self->{floorclip}[$x] - 1 if $bottom >= $self->{floorclip}[$x];
            if ($top <= $bottom) {
                $self->{ceilingplane}{top}[$x] = $top;
                $self->{ceilingplane}{bottom}[$x] = $bottom;
            }
        }
        my $yh = shar($self->{bottomfrac}, HEIGHTBITS);
        $yh = $self->{floorclip}[$x] - 1 if $yh >= $self->{floorclip}[$x];
        if ($self->{markfloor} && $self->{floorplane}) {
            my $top = $yh + 1;
            my $bottom = $self->{floorclip}[$x] - 1;
            $top = $self->{ceilingclip}[$x] + 1 if $top <= $self->{ceilingclip}[$x];
            if ($top <= $bottom) {
                $self->{floorplane}{top}[$x] = $top;
                $self->{floorplane}{bottom}[$x] = $bottom;
            }
        }
        if ($self->{segtextured}) {
            my $angle = ushr(as_u32($self->{rw_centerangle} + $self->{xtoviewangle}[$x]), ANGLETOFINESHIFT);
            my $tanv = $Doom::Tables::FINETANGENT[$angle & (int(FINEANGLES / 2) - 1)];
            $texturecolumn = shar($self->{rw_offset} - fixed_mul($tanv, $self->{rw_distance}), FRACBITS);
            my $index = ushr($self->{rw_scale}, LIGHTSCALESHIFT);
            $index = MAXLIGHTSCALE - 1 if $index >= MAXLIGHTSCALE;
            $self->{dc_colormap} = $self->{fixedcolormap} || $self->{res}->colormap($self->{walllights}[$index]);
            $self->{dc_x} = $x;
            $self->{dc_iscale} = $self->{rw_scale} ? int(4294967295 / $self->{rw_scale}) : 0;
        }
        if ($self->{midtexture}) {
            $self->{dc_yl} = $yl;
            $self->{dc_yh} = $yh;
            $self->{dc_texturemid} = $self->{rw_midtexturemid};
            $self->{dc_source} = $self->{res}->get_column($self->{midtexture}, $texturecolumn);
            $self->_draw_column;
            $self->{ceilingclip}[$x] = $self->{viewheight};
            $self->{floorclip}[$x] = -1;
        }
        else {
            if ($self->{toptexture}) {
                my $mid = shar($self->{pixhigh}, HEIGHTBITS);
                $self->{pixhigh} += $self->{pixhighstep};
                $mid = $self->{floorclip}[$x] - 1 if $mid >= $self->{floorclip}[$x];
                if ($mid >= $yl) {
                    $self->{dc_yl} = $yl;
                    $self->{dc_yh} = $mid;
                    $self->{dc_texturemid} = $self->{rw_toptexturemid};
                    $self->{dc_source} = $self->{res}->get_column($self->{toptexture}, $texturecolumn);
                    $self->_draw_column;
                    $self->{ceilingclip}[$x] = $mid;
                }
                else {
                    $self->{ceilingclip}[$x] = $yl - 1;
                }
            }
            elsif ($self->{markceiling}) {
                $self->{ceilingclip}[$x] = $yl - 1;
            }
            if ($self->{bottomtexture}) {
                my $mid = shar($self->{pixlow} + HEIGHTUNIT - 1, HEIGHTBITS);
                $self->{pixlow} += $self->{pixlowstep};
                $mid = $self->{ceilingclip}[$x] + 1 if $mid <= $self->{ceilingclip}[$x];
                if ($mid <= $yh) {
                    $self->{dc_yl} = $mid;
                    $self->{dc_yh} = $yh;
                    $self->{dc_texturemid} = $self->{rw_bottomtexturemid};
                    $self->{dc_source} = $self->{res}->get_column($self->{bottomtexture}, $texturecolumn);
                    $self->_draw_column;
                    $self->{floorclip}[$x] = $mid;
                }
                else {
                    $self->{floorclip}[$x] = $yh + 1;
                }
            }
            elsif ($self->{markfloor}) {
                $self->{floorclip}[$x] = $yh + 1;
            }
            if ($self->{maskedtexture} && $self->{maskedtexturecol}) {
                $self->{maskedtexturecol}[$x - $self->{rw_start}] = $texturecolumn;
            }
        }
        $self->{rw_scale} += $self->{rw_scalestep};
        $self->{topfrac} += $self->{topstep};
        $self->{bottomfrac} += $self->{bottomstep};
        $self->{rw_x}++;
    }
    return;
}

sub _draw_column {
    my $pt = $Doom::Profile::ON ? Doom::Profile::now() : 0;
    my ($self) = @_;
    my $count = $self->{dc_yh} - $self->{dc_yl};
    if ($count < 0 || $self->{dc_x} < 0 || $self->{dc_x} >= $self->{viewwidth}) {
        Doom::Profile::add('column', Doom::Profile::now() - $pt) if $pt;
        return;
    }
    my $yl = $self->{dc_yl};
    $yl = 0 if $yl < 0;
    $yl = SCREENHEIGHT - 1 if $yl > SCREENHEIGHT - 1;
    my $x = $self->{dc_x};
    my $wide = 0;
    if ($self->{detailshift}) {
        $x <<= 1;
        if ($x < 0 || $x + 1 >= SCREENWIDTH) {
            Doom::Profile::add('column', Doom::Profile::now() - $pt) if $pt;
            return;
        }
        $wide = 1;
    }
    my $dest = $self->{ylookup}[$yl] + $self->{columnofs}[$x];
    my $fracstep = $self->{dc_iscale};
    my $frac = $self->{dc_texturemid} + ($self->{dc_yl} - $self->{centery}) * $fracstep;
    my $src = $self->{dc_source};
    my $cm = $self->{dc_colormap};
    my $slen = length($src);
    my $limit = SCREENWIDTH * SCREENHEIGHT;
    while ($count >= 0 && $dest < $limit) {
        my $idx = ($frac >> FRACBITS) & 127;
        if ($slen) {
            my $pix = ord(substr($src, $idx % $slen, 1));
            my $val = $pix < length($cm) ? ord(substr($cm, $pix, 1)) : $pix;
            if ($wide && $dest + 1 < $limit) {
                substr($self->{fb}, $dest, 2) = chr($val) x 2;
            }
            else {
                substr($self->{fb}, $dest, 1) = chr($val);
            }
        }
        $dest += SCREENWIDTH;
        $frac = as_i32($frac + $fracstep);
        $count--;
    }
    Doom::Profile::add('column', Doom::Profile::now() - $pt) if $pt;
    return;
}

sub draw_masked {
    my ($self) = @_;
    for my $ds (reverse @{$self->{drawsegs}}) {
        $self->render_masked_seg_range($ds, $ds->{x1}, $ds->{x2}) if $ds->{maskedtexturecol};
    }
    return;
}

sub render_masked_seg_range {
    my ($self, $ds, $x1, $x2) = @_;
    return if !$ds->{maskedtexturecol} || !$ds->{curline};
    my $line = $ds->{curline};
    my $front = $line->{frontsector};
    my $back = $line->{backsector};
    my $sidedef = $line->{sidedef};
    my $texnum = $sidedef ? $sidedef->{midtexture} : 0;
    return if !$texnum || !$back || !$front;
    my $lightnum = ($front->{lightlevel} >> 4) + $self->{extralight};
    $lightnum-- if $line->{v1}{y} == $line->{v2}{y};
    $lightnum++ if $line->{v1}{x} == $line->{v2}{x};
    $lightnum = 0 if $lightnum < 0;
    $lightnum = LIGHTLEVELS - 1 if $lightnum > LIGHTLEVELS - 1;
    my $walllights = $self->{scalelight}[$lightnum];
    my $dc_texturemid;
    if ($line->{linedef}{flags} & ML_DONTPEGBOTTOM) {
        $dc_texturemid = $front->{floorheight} > $back->{floorheight} ? $front->{floorheight} : $back->{floorheight};
        $dc_texturemid = $dc_texturemid + $self->{res}->texture_height($texnum) - $self->{viewz};
    }
    else {
        $dc_texturemid = $front->{ceilingheight} < $back->{ceilingheight} ? $front->{ceilingheight} : $back->{ceilingheight};
        $dc_texturemid = $dc_texturemid - $self->{viewz};
    }
    $dc_texturemid += $sidedef->{rowoffset};
    my $spryscale = $ds->{scale1} + ($x1 - $ds->{x1}) * $ds->{scalestep};
    for (my $dc_x = $x1; $dc_x <= $x2; $dc_x++) {
        my $i = $dc_x - $ds->{x1};
        if ($i < 0 || $i >= @{$ds->{maskedtexturecol}}) {
            $spryscale += $ds->{scalestep};
            next;
        }
        my $tcol = $ds->{maskedtexturecol}[$i];
        if ($tcol != SHRT_MAX) {
            my $index = $spryscale > 0 ? ushr($spryscale, LIGHTSCALESHIFT) : 0;
            $index = MAXLIGHTSCALE - 1 if $index >= MAXLIGHTSCALE;
            $self->{dc_colormap} = $self->{fixedcolormap} || $self->{res}->colormap($walllights->[$index]);
            $self->{dc_x} = $dc_x;
            $self->{dc_iscale} = $spryscale ? int(4294967295 / $spryscale) : 0;
            $self->{dc_texturemid} = $dc_texturemid;
            my $sprtopscreen = $self->{centeryfrac} - fixed_mul($dc_texturemid, $spryscale);
            my $mceil = $i < @{$ds->{sprtopclip}} ? $ds->{sprtopclip}[$i] : -1;
            my $mfloor = $i < @{$ds->{sprbottomclip}} ? $ds->{sprbottomclip}[$i] : $self->{viewheight};
            my @posts = $self->{res}->column_posts($texnum, $tcol);
            $self->_draw_masked_column(\@posts, $sprtopscreen, $spryscale, $mceil, $mfloor);
            $ds->{maskedtexturecol}[$i] = SHRT_MAX;
        }
        $spryscale += $ds->{scalestep};
    }
    return;
}

sub _ashr {
    my ($n, $bits) = @_;
    return 0 if $bits <= 0;
    return int($n / (1 << $bits)) if $n >= 0;
    my $mask = (1 << $bits) - 1;
    return -int((-$n + $mask) / (1 << $bits));
}

sub _draw_masked_column {
    my ($self, $posts, $sprtopscreen, $spryscale, $mceil, $mfloor) = @_;
    my $basemid = $self->{dc_texturemid};
    for my $post (@$posts) {
        my ($topdelta, $pixels) = @$post;
        next if !length($pixels);
        my $topscreen = $sprtopscreen + $spryscale * $topdelta;
        my $bottomscreen = $topscreen + $spryscale * length($pixels);
        my $yl = _ashr($topscreen + FRACUNIT - 1, FRACBITS);
        my $yh = _ashr($bottomscreen - 1, FRACBITS);
        $yh = $mfloor - 1 if $yh >= $mfloor;
        $yl = $mceil + 1 if $yl <= $mceil;
        $yl = 0 if $yl < 0;
        $yh = $self->{viewheight} - 1 if $yh >= $self->{viewheight};
        if ($yl <= $yh) {
            my $src = length($pixels) >= 128 ? substr($pixels, 0, 128) : $pixels . ("\0" x (128 - length($pixels)));
            $self->{dc_yl} = $yl;
            $self->{dc_yh} = $yh;
            $self->{dc_source} = $src;
            $self->{dc_texturemid} = $basemid - ($topdelta << FRACBITS);
            $self->_draw_column;
        }
    }
    $self->{dc_texturemid} = $basemid;
    return;
}

sub _draw_planes {
    my $pt = $Doom::Profile::ON ? Doom::Profile::now() : 0;
    my ($self) = @_;
    my $res = $self->{res};
    my @cmcache = map { $res->colormap($_) } 0 .. 32;
    my $yslope = $self->{yslope};
    my $ylookup = $self->{ylookup};
    my $distscale = $self->{distscale};
    my $xtoview = $self->{xtoviewangle};
    my $cols = $self->{columnofs};
    my $finesine = \@Doom::Tables::FINESINE;
    my $viewx = $self->{viewx};
    my $viewy = $self->{viewy};
    my $viewangle = $self->{viewangle};
    my $viewz = $self->{viewz};
    my $viewh = $self->{viewheight};
    my $vieww = $self->{viewwidth};
    my $extralight = $self->{extralight};
    my $wide = $self->{detailshift};
    my $fixedcm = $self->{fixedcolormap};
    my $sky = $res->{skyflatnum};
    my $zlight = $self->{zlight};
    my $limit = SCREENWIDTH * SCREENHEIGHT;
    my $quarter = int(FINEANGLES / 4);
    for my $pl (@{$self->{visplanes}}) {
        next if $pl->{minx} > $pl->{maxx};
        if ($pl->{picnum} == $sky) {
            $self->{dc_iscale} = int(9 * FRACUNIT / 10);
            $self->{dc_colormap} = $res->colormap(0);
            $self->{dc_texturemid} = 100 * FRACUNIT;
            for my $x ($pl->{minx} .. $pl->{maxx}) {
                my ($yl, $yh) = ($pl->{top}[$x], $pl->{bottom}[$x]);
                if ($yl <= $yh && $yl < 0xFF) {
                    my $ang = ushr(as_u32($viewangle + $xtoview->[$x]), ANGLETOSKYSHIFT);
                    $self->{dc_x} = $x;
                    $self->{dc_yl} = $yl;
                    $self->{dc_yh} = $yh;
                    $self->{dc_source} = $res->get_column($res->{skytexture}, $ang);
                    $self->_draw_column;
                }
            }
            next;
        }
        my $light = ($pl->{lightlevel} >> 4) + $extralight;
        $light = 0 if $light < 0;
        $light = LIGHTLEVELS - 1 if $light > LIGHTLEVELS - 1;
        my $planezlight = $zlight->[$light];
        my $flat = $res->flat_pixels($pl->{picnum});
        my $flen = length($flat);
        my $planeheight = abs_fixed($pl->{height} - $viewz);
        next if $planeheight == 0;
        my $x0 = $pl->{minx} < 0 ? 0 : $pl->{minx};
        my $x1 = $pl->{maxx} >= $vieww ? $vieww - 1 : $pl->{maxx};
        my $fb = $self->{fb};
        my $bottom = $viewh - 1;
        for my $x ($x0 .. $x1) {
            my ($t1, $b1) = ($pl->{top}[$x], $pl->{bottom}[$x]);
            next if $t1 > $b1 || $t1 == 0xFF;
            my $y1 = $b1 < $bottom ? $b1 : $bottom;
            my $ang = ushr(as_u32($viewangle + $xtoview->[$x]), ANGLETOFINESHIFT) & FINEMASK;
            my $sin = $finesine->[$ang];
            my $cos = $finesine->[($ang + $quarter) & FINEMASK];
            my $scale = $distscale->[$x];
            my $xx = $wide ? ($x << 1) : $x;
            my $col = $cols->[$xx];
            for my $y ($t1 .. $y1) {
                my $distance = fixed_mul($planeheight, $yslope->[$y]);
                my $length = fixed_mul($distance, $scale);
                my $ds_xfrac = $viewx + fixed_mul($cos, $length);
                my $ds_yfrac = -$viewy - fixed_mul($sin, $length);
                my $index = ushr($distance, LIGHTZSHIFT);
                $index = MAXLIGHTZ - 1 if $index > MAXLIGHTZ - 1;
                my $level = $planezlight->[$index];
                $level = 0 if $level < 0;
                $level = 32 if $level > 32;
                my $cm = $fixedcm || $cmcache[$level];
                my $cml = length($cm);
                my $spot = (($ds_xfrac >> 16) & 63) | (($ds_yfrac >> 10) & 0x0FC0);
                my $pix = ord(substr($flat, $spot < $flen ? $spot : 0, 1));
                $pix = ord(substr($cm, $pix, 1)) if $pix < $cml;
                my $off = $ylookup->[$y] + $col;
                if ($wide && $off + 1 < $limit) {
                    substr($fb, $off, 2) = chr($pix) x 2;
                }
                else {
                    substr($fb, $off, 1) = chr($pix);
                }
            }
        }
        $self->{fb} = $fb;
    }
    Doom::Profile::add('planes', Doom::Profile::now() - $pt) if $pt;
    return;
}

1;
