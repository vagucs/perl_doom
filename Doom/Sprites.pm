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
# Coisas do mapa e a pistola na mao. Igual a doom/sprites.py.
# O quadro da arma segue o tiro. O monstro anda no Enemy.pm.

package Doom::Sprites;

use strict;
use warnings;

use Doom::Collision qw(set_thing_position);
use Doom::Compat qw(as_i32 as_u32 fixed_div fixed_mul shar);
use Doom::Defs qw(
    ANG45 FRACBITS FRACUNIT
    SCREENWIDTH SIL_BOTTOM SIL_TOP
);
use Doom::Info qw(
    sprite_name mobj_type_for_doomednum
    MI_DOOMEDNUM MI_FLAGS MI_HEIGHT MI_RADIUS MI_SPAWNHEALTH MI_SPAWNSTATE
);

use Exporter qw(import);
our @EXPORT_OK = qw(prepare_sprites spawn_map_things draw_sprites draw_gun);

use constant BASEYCENTER => 100;
use constant WEAPONTOP => 32 * FRACUNIT;
use constant MINZ => 4 * FRACUNIT;
use constant MAX_SPRITE_FRAMES => 29;
use constant MF_NOSECTOR => 8;
use constant MF_SPAWNCEILING => 256;
use constant MF_SHADOW => 0x40000;
use constant MF_AMBUSH => 32;
use constant FF_FRAMEMASK => 0x7FFF;

my @FUZZ_DIR = (
    1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1, -1, -1, -1, -1, 1, -1, -1, 1,
    1, 1, 1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, 1, -1, 1, 1, -1, 1,
);
my $fuzzpos = 0;
my $gun_patch;

sub _ashr {
    my ($n, $bits) = @_;
    return 0 if $bits <= 0;
    return $n >> $bits if $n >= 0;
    my $mask = (1 << $bits) - 1;
    return -((-$n + $mask) >> $bits);
}

sub _lump_name {
    my ($wad, $i) = @_;
    my $lump = $wad->{lumps}[$i];
    return $lump ? $lump->{name} : '';
}

sub _install_sprite_lump {
    my ($frames, $lump, $frame, $rotation, $flipped) = @_;
    return 0 if $frame < 0 || $frame >= MAX_SPRITE_FRAMES || $rotation < 0 || $rotation > 8;
    my $sf = $frames->[$frame];
    if ($rotation == 0) {
        return 1 if $sf->{rotate} == 1;
        $sf->{rotate} = 0;
        for my $r (0 .. 7) {
            $sf->{lump}[$r] = $lump;
            $sf->{flip}[$r] = $flipped ? 1 : 0;
        }
        return 1;
    }
    return 1 if $sf->{rotate} == 0;
    $sf->{rotate} = 1;
    my $idx = $rotation - 1;
    if ($sf->{lump}[$idx] < 0) {
        $sf->{lump}[$idx] = $lump;
        $sf->{flip}[$idx] = $flipped ? 1 : 0;
    }
    return 1;
}

sub init_sprite_defs {
    my ($wad) = @_;
    my $start = $wad->check_num_for_name('S_START');
    my $end = $wad->check_num_for_name('S_END');
    $start = $wad->check_num_for_name('SS_START') if $start < 0;
    $end = $wad->check_num_for_name('SS_END') if $end < 0;
    my ($first, $last);
    if ($start >= 0 && $end > $start) {
        ($first, $last) = ($start + 1, $end - 1);
    }
    else {
        ($first, $last) = (0, $wad->num_lumps - 1);
    }
    my %buckets;
    for my $lump ($first .. $last) {
        my $name = _lump_name($wad, $lump);
        next if length($name) < 6;
        push @{$buckets{substr($name, 0, 4)}}, $lump;
    }
    my %result;
    for my $sprname (keys %buckets) {
        my @frames = map { { rotate => -1, lump => [(-1) x 8], flip => [(0) x 8] } } 1 .. MAX_SPRITE_FRAMES;
        my $maxframe = -1;
        for my $lump (@{$buckets{$sprname}}) {
            my $name = _lump_name($wad, $lump);
            my $frame = ord(substr($name, 4, 1)) - ord('A');
            my $rotation = ord(substr($name, 5, 1)) - ord('0');
            if (_install_sprite_lump(\@frames, $lump, $frame, $rotation, 0)) {
                $maxframe = $frame if $frame > $maxframe;
            }
            if (length($name) >= 8) {
                my $ch = substr($name, 6, 1);
                if ($ch ge 'A' && $ch le ']') {
                    my $frame2 = ord($ch) - ord('A');
                    my $rotation2 = ord(substr($name, 7, 1)) - ord('0');
                    if (_install_sprite_lump(\@frames, $lump, $frame2, $rotation2, 1)) {
                        $maxframe = $frame2 if $frame2 > $maxframe;
                    }
                }
            }
        }
        next if $maxframe < 0;
        for my $frame_i (0 .. $maxframe) {
            my $slot = $frames[$frame_i];
            if ($slot->{rotate} < 0) {
                warn "R_InitSprites: No patches found for $sprname frame " . chr(ord('A') + $frame_i) . "\n";
                $slot->{rotate} = 0;
            }
        }
        $result{$sprname} = [ @frames[0 .. $maxframe] ];
    }
    return \%result;
}

sub lookup_sprite {
    my ($res, $name, $ang_to_thing, $moangle, $frame) = @_;
    my $base = uc substr($name // '', 0, 4);
    my $sprframes = $res->{sprites}{$base} or return;
    my $fi = $frame & FF_FRAMEMASK;
    return if $fi > $#$sprframes;
    my $sf = $sprframes->[$fi];
    my ($lump, $flip);
    if ($sf->{rotate}) {
        my $rot = (as_u32($ang_to_thing - $moangle + ((ANG45 >> 1) * 9)) >> 29) & 7;
        ($lump, $flip) = ($sf->{lump}[$rot], $sf->{flip}[$rot]);
    }
    else {
        ($lump, $flip) = ($sf->{lump}[0], $sf->{flip}[0]);
    }
    return if !defined $lump || $lump < 0;
    return [ $lump, $flip ];
}

sub prepare_sprites {
    my ($res) = @_;
    $res->{sprites} = init_sprite_defs($res->{wad});
    my $found = lookup_sprite($res, 'PISG', 0, 0, 0);
    $gun_patch = $found ? $res->{wad}->cache_lump_num($found->[0]) : undef;
    return;
}

sub spawn_map_things {
    my ($world, $skill) = @_;
    $skill = 2 if !defined $skill;
    my $bit = 2;
    $bit = 1 if $skill <= 1;
    $bit = 4 if $skill >= 3;
    $world->{mobjs} = [];
    for my $mt (@{$world->{things}}) {
        my $kind = $mt->{type};
        next if $kind == 11 || ($kind >= 1 && $kind <= 4);
        next if !($mt->{options} & $bit);
        next if $mt->{options} & 16;
        my $typ = mobj_type_for_doomednum($kind);
        next if $typ < 0;
        my $info = $Doom::Info::MOBJINFO[$typ];
        my $flags = $info->[MI_FLAGS];
        my $x = $mt->{x} * FRACUNIT;
        my $y = $mt->{y} * FRACUNIT;
        my $sub = $world->point_in_subsector($x, $y);
        my $mo = {
            x => $x, y => $y, z => 0, angle => 0,
            radius => $info->[MI_RADIUS], height => $info->[MI_HEIGHT],
            floorz => $sub->{sector}{floorheight},
            ceilingz => $sub->{sector}{ceilingheight},
            flags => $flags, health => $info->[MI_SPAWNHEALTH],
            type => $typ, doomednum => $info->[MI_DOOMEDNUM],
            player => undef, sprite => '', frame => 0,
            istate => 0, tics => -1, alive => 1,
            reactiontime => $info->[5] || 0, movedir => 8, movecount => 0,
            threshold => 0, lastlook => 0, momx => 0, momy => 0, momz => 0,
        };
        if ($flags & MF_SPAWNCEILING) {
            $mo->{z} = $mo->{ceilingz} - $mo->{height};
        }
        else {
            $mo->{z} = $mo->{floorz};
        }
        my $st = $Doom::Info::STATES[$info->[MI_SPAWNSTATE]];
        $mo->{istate} = $info->[MI_SPAWNSTATE];
        $mo->{tics} = $st->[2];
        $mo->{sprite} = sprite_name($st->[0]);
        $mo->{frame} = $st->[1];
        $mo->{angle} = as_u32(int($mt->{angle} / 45) * ANG45);
        $mo->{flags} |= MF_AMBUSH if $mt->{options} & 8;
        push @{$world->{mobjs}}, $mo;
        set_thing_position($world, $mo);
    }
    return scalar @{$world->{mobjs}};
}

sub _patch_size {
    my ($patch) = @_;
    return unpack('s<s<s<s<', substr($patch, 0, 8));
}

sub _point_on_seg_side {
    my ($x, $y, $line) = @_;
    my ($lx, $ly) = ($line->{v1}{x}, $line->{v1}{y});
    my $ldx = $line->{v2}{x} - $lx;
    my $ldy = $line->{v2}{y} - $ly;
    if ($ldx == 0) {
        if ($x <= $lx) {
            return $ldy > 0 ? 1 : 0;
        }
        return $ldy < 0 ? 1 : 0;
    }
    if ($ldy == 0) {
        if ($y <= $ly) {
            return $ldx < 0 ? 1 : 0;
        }
        return $ldx > 0 ? 1 : 0;
    }
    my $dx = $x - $lx;
    my $dy = $y - $ly;
    my $left = fixed_mul(shar($ldy, FRACBITS), $dx);
    my $right = fixed_mul($dy, shar($ldx, FRACBITS));
    return $right < $left ? 0 : 1;
}

sub _clip_against_walls {
    my ($renderer, $spr) = @_;
    my ($x1, $x2) = ($spr->{x1}, $spr->{x2});
    my @clipbot = ((-2) x SCREENWIDTH);
    my @cliptop = ((-2) x SCREENWIDTH);
    for my $ds (reverse @{$renderer->{drawsegs}}) {
        next if $ds->{x1} > $x2 || $ds->{x2} < $x1;
        next if !$ds->{silhouette} && !$ds->{maskedtexturecol};
        my $r1 = $ds->{x1} > $x1 ? $ds->{x1} : $x1;
        my $r2 = $ds->{x2} < $x2 ? $ds->{x2} : $x2;
        my $scale = $ds->{scale1} > $ds->{scale2} ? $ds->{scale1} : $ds->{scale2};
        my $lowscale = $ds->{scale1} < $ds->{scale2} ? $ds->{scale1} : $ds->{scale2};
        my $in_front = $scale < $spr->{scale} || (
            $lowscale < $spr->{scale}
            && $ds->{curline}
            && _point_on_seg_side($spr->{gx}, $spr->{gy}, $ds->{curline}) == 0
        );
        if ($in_front) {
            $renderer->render_masked_seg_range($ds, $r1, $r2) if $ds->{maskedtexturecol};
            next;
        }
        my $silhouette = $ds->{silhouette};
        $silhouette &= ~SIL_BOTTOM if $spr->{gz} >= ($ds->{bsilheight} // 0);
        $silhouette &= ~SIL_TOP if $spr->{gzt} <= ($ds->{tsilheight} // 0);
        for my $x ($r1 .. $r2) {
            my $i = $x - $ds->{x1};
            next if $i < 0 || $i > $#{$ds->{sprtopclip}};
            if (($silhouette & SIL_BOTTOM) && $clipbot[$x] == -2) {
                $clipbot[$x] = $ds->{sprbottomclip}[$i];
            }
            if (($silhouette & SIL_TOP) && $cliptop[$x] == -2) {
                $cliptop[$x] = $ds->{sprtopclip}[$i];
            }
        }
    }
    my $viewh = $renderer->{viewheight};
    for my $x ($x1 .. $x2) {
        $clipbot[$x] = $viewh if $clipbot[$x] == -2;
        $cliptop[$x] = -1 if $cliptop[$x] == -2;
    }
    return (\@cliptop, \@clipbot);
}

sub _project {
    my ($renderer, $mo) = @_;
    return if !$mo->{sprite} || $mo->{player} || ($mo->{flags} & MF_NOSECTOR);
    my $tr_x = as_i32($mo->{x} - $renderer->{viewx});
    my $tr_y = as_i32($mo->{y} - $renderer->{viewy});
    my $gxt = fixed_mul($tr_x, $renderer->{viewcos});
    my $gyt = -fixed_mul($tr_y, $renderer->{viewsin});
    my $tz = $gxt - $gyt;
    return if $tz < MINZ;
    my $xscale = fixed_div($renderer->{projection}, $tz);
    $gxt = -fixed_mul($tr_x, $renderer->{viewsin});
    $gyt = fixed_mul($tr_y, $renderer->{viewcos});
    my $tx = -($gyt + $gxt);
    return if abs($tx) > $tz * 4;
    my $found = lookup_sprite(
        $renderer->{res}, $mo->{sprite},
        $renderer->point_to_angle($mo->{x}, $mo->{y}), $mo->{angle}, $mo->{frame},
    );
    return if !$found;
    my ($lump, $flip) = @$found;
    my $patch = $renderer->{res}{wad}->cache_lump_num($lump);
    return if !defined $patch || length($patch) < 8;
    my ($w, undef, $left, $top) = _patch_size($patch);
    $tx -= $left * FRACUNIT;
    my $x1 = _ashr($renderer->{centerxfrac} + fixed_mul($tx, $xscale), FRACBITS);
    return if $x1 > $renderer->{viewwidth};
    $tx += $w * FRACUNIT;
    my $x2 = _ashr($renderer->{centerxfrac} + fixed_mul($tx, $xscale), FRACBITS) - 1;
    return if $x2 < 0;
    my $iscale = $xscale ? fixed_div(FRACUNIT, $xscale) : FRACUNIT;
    my $xiscale = $flip ? -$iscale : $iscale;
    my $startfrac = $flip ? (($w << FRACBITS) - 1) : 0;
    my $vis_x1 = $x1 > 0 ? $x1 : 0;
    my $vis_x2 = $x2 < $renderer->{viewwidth} - 1 ? $x2 : $renderer->{viewwidth} - 1;
    $startfrac += $xiscale * ($vis_x1 - $x1) if $vis_x1 > $x1;
    return {
        mo => $mo, patch => $patch, w => $w,
        scale => $xscale << $renderer->{detailshift},
        gx => $mo->{x}, gy => $mo->{y}, gz => $mo->{z},
        gzt => $mo->{z} + $top * FRACUNIT,
        texturemid => $mo->{z} + $top * FRACUNIT - $renderer->{viewz},
        x1 => $vis_x1, x2 => $vis_x2,
        xiscale => $xiscale, startfrac => $startfrac,
    };
}

sub _draw_fuzz_pixel {
    my ($renderer, $x, $y, $cm) = @_;
    my $fb = \$renderer->{fb};
    my $col = $renderer->{detailshift} ? ($x << 1) : $x;
    my $dest = $renderer->{ylookup}[$y] + $renderer->{columnofs}[$col];
    my $src = $dest + $FUZZ_DIR[$fuzzpos] * SCREENWIDTH;
    $fuzzpos = ($fuzzpos + 1) % @FUZZ_DIR;
    $src = $dest if $src < 0 || $src >= length($$fb);
    my $pix = ord(substr($$fb, $src, 1));
    my $val = $pix < length($cm) ? ord(substr($cm, $pix, 1)) : $pix;
    substr($$fb, $dest, 1) = chr($val);
    substr($$fb, $dest + 1, 1) = chr($val) if $renderer->{detailshift} && $dest + 1 < length($$fb);
    return;
}

sub _draw_sprite {
    my ($renderer, $spr, $clip_walls) = @_;
    $clip_walls = 1 if !defined $clip_walls;
    my $patch = $spr->{patch};
    my $patch_w = $spr->{w};
    my $iscale = $spr->{xiscale};
    my $spryscale = $spr->{scale};
    my $y_iscale = abs($iscale) >> $renderer->{detailshift};
    $y_iscale = 1 if $y_iscale < 1;
    my $sprtopscreen = $renderer->{centeryfrac} - fixed_mul($spr->{texturemid}, $spryscale);
    my ($cliptop, $clipbot);
    if ($clip_walls) {
        ($cliptop, $clipbot) = _clip_against_walls($renderer, $spr);
    }
    else {
        $cliptop = [(-1) x SCREENWIDTH];
        $clipbot = [($renderer->{viewheight}) x SCREENWIDTH];
    }
    my @colofs;
    for my $c (0 .. ($patch_w > 1 ? $patch_w : 1) - 1) {
        $colofs[$c] = unpack('V', substr($patch, 8 + $c * 4, 4));
    }
    my $mo = $spr->{mo};
    my $fuzz = $mo && ($mo->{flags} & MF_SHADOW);
    my $cm = $fuzz ? $renderer->{res}->colormap(6)
        : ($renderer->{fixedcolormap} || $renderer->{res}->colormap(0));
    my $frac = $spr->{startfrac};
    my $fb = \$renderer->{fb};
    my $limit = length($$fb);
    for my $x ($spr->{x1} .. $spr->{x2}) {
        my $col = _ashr($frac, FRACBITS);
        if ($col >= 0 && $col < $patch_w) {
            my $column = $colofs[$col];
            while (defined $column && $column + 1 < length($patch)) {
                my $topdelta = ord(substr($patch, $column, 1));
                last if $topdelta == 0xFF;
                my $length = ord(substr($patch, $column + 1, 1));
                my $source = $column + 3;
                my $topscreen = $sprtopscreen + $spryscale * $topdelta;
                my $bottomscreen = $topscreen + $spryscale * $length;
                my $yl = _ashr($topscreen + FRACUNIT - 1, FRACBITS);
                my $yh = _ashr($bottomscreen - 1, FRACBITS);
                my $topc = $cliptop->[$x];
                my $botc = $clipbot->[$x];
                $topc = -1 if !defined $topc;
                $botc = $renderer->{viewheight} if !defined $botc;
                $yl = $topc + 1 if $yl <= $topc;
                $yh = $botc - 1 if $yh >= $botc;
                $yl = 0 if $yl < 0;
                $yh = $renderer->{viewheight} - 1 if $yh >= $renderer->{viewheight};
                if ($fuzz) {
                    $yl = 1 if $yl <= 0;
                    $yh = $renderer->{viewheight} - 2 if $yh >= $renderer->{viewheight} - 1;
                }
                if ($yl <= $yh) {
                    my $texfrac = fixed_mul(($yl << FRACBITS) - $topscreen, $y_iscale);
                    $texfrac = 0 if $texfrac < 0;
                    for my $y ($yl .. $yh) {
                        if ($fuzz) {
                            _draw_fuzz_pixel($renderer, $x, $y, $cm);
                        }
                        else {
                            my $idx = $texfrac >> FRACBITS;
                            if ($idx >= 0 && $idx < $length) {
                                my $pix = ord(substr($patch, $source + $idx, 1));
                                my $val = $pix < length($cm) ? ord(substr($cm, $pix, 1)) : $pix;
                                my $off = $renderer->{ylookup}[$y] + $renderer->{columnofs}[$x];
                                if ($off >= 0 && $off < $limit) {
                                    substr($$fb, $off, 1) = chr($val);
                                }
                            }
                        }
                        $texfrac += $y_iscale;
                    }
                }
                $column += $length + 4;
            }
        }
        $frac += $iscale;
    }
    return;
}

sub draw_sprites {
    my ($renderer, $world) = @_;
    my @vis;
    for my $mo (@{$world->{mobjs}}) {
        my $item = _project($renderer, $mo);
        push @vis, $item if $item;
    }
    @vis = sort { $a->{scale} <=> $b->{scale} } @vis;
    for my $spr (@vis) {
        _draw_sprite($renderer, $spr, 1);
    }
    $renderer->draw_masked;
    return;
}

sub draw_psprite {
    my ($renderer, $patch, $sx, $sy) = @_;
    return if !defined $patch || length($patch) < 8;
    my ($w, undef, $left, $top) = _patch_size($patch);
    my $pspritescale = $renderer->{pspritescale} || FRACUNIT;
    my $pspriteiscale = $renderer->{pspriteiscale} || FRACUNIT;
    my $tx = $sx - 160 * FRACUNIT;
    $tx -= $left * FRACUNIT;
    my $x1 = _ashr($renderer->{centerxfrac} + fixed_mul($tx, $pspritescale), FRACBITS);
    return if $x1 > $renderer->{viewwidth};
    $tx += $w * FRACUNIT;
    my $x2 = _ashr($renderer->{centerxfrac} + fixed_mul($tx, $pspritescale), FRACBITS) - 1;
    return if $x2 < 0;
    my $vis_x1 = $x1 > 0 ? $x1 : 0;
    my $vis_x2 = $x2 < $renderer->{viewwidth} - 1 ? $x2 : $renderer->{viewwidth} - 1;
    my $startfrac = 0;
    $startfrac += $pspriteiscale * ($vis_x1 - $x1) if $vis_x1 > $x1;
    my $texturemid = BASEYCENTER * FRACUNIT + int(FRACUNIT / 2) - ($sy - $top * FRACUNIT);
    _draw_sprite($renderer, {
        patch => $patch, w => $w,
        scale => $pspritescale << $renderer->{detailshift},
        texturemid => $texturemid,
        x1 => $vis_x1, x2 => $vis_x2,
        xiscale => $pspriteiscale, startfrac => $startfrac,
    }, 0);
    return;
}

sub _gun_patch {
    my ($renderer, $name, $frame) = @_;
    return if !$renderer || !$renderer->{res} || !$name;
    my $found = lookup_sprite($renderer->{res}, $name, 0, 0, $frame || 0);
    return if !$found;
    return $renderer->{res}{wad}->cache_lump_num($found->[0]);
}

sub draw_gun {
    my ($renderer, $mo) = @_;
    my $name = ($mo && $mo->{gunsprite}) ? $mo->{gunsprite} : 'PISG';
    my $frame = ($mo && defined $mo->{gunframe}) ? $mo->{gunframe} : 0;
    my $patch = _gun_patch($renderer, $name, $frame);
    $patch = $gun_patch if !$patch;
    draw_psprite($renderer, $patch, FRACUNIT, WEAPONTOP);
    if ($mo && ($mo->{flash_tics} || 0) > 0 && $mo->{gunflash}) {
        my $flash = _gun_patch($renderer, $mo->{gunflash}, $mo->{gunflashframe} || 0);
        draw_psprite($renderer, $flash, FRACUNIT, WEAPONTOP) if $flash;
    }
    return;
}

1;
