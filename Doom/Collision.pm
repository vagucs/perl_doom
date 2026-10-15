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
# O corpo para na linha e escorrega. Igual a doom/collision.py.

package Doom::Collision;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(
    thrust xy_move set_thing_position try_move
    use_lines change_sector line_attack aim_slope approx_distance
);

use Doom::Compat qw(as_i32 as_u32 fixed_div fixed_mul shar);
use Doom::Defs qw(
    ANG90 ANG180
    BOXLEFT BOXRIGHT BOXBOTTOM BOXTOP
    FRACBITS FRACUNIT
    FRICTION MAPBLOCKSHIFT MAPBLOCKSIZE MAPBTOFRAC MAXMOVE MAXRADIUS MAXSTEP
    MF_DROPOFF MF_FLOAT MF_MISSILE MF_NOCLIP MF_SHOOTABLE MF_SOLID MF_SPECIAL MF_TELEPORT
    ML_BLOCKING ML_BLOCKMONSTERS ML_TWOSIDED
    PT_ADDLINES STOPSPEED
);
use Doom::Pickups;
use Doom::Tables qw(fine_cos fine_sin slope_div);

use constant USERANGE => 64 * FRACUNIT;
use constant PT_ADDTHINGS => 2;

use constant INT_MAX => 0x7FFFFFFF;

our $CEILINGLINE;
our $_earlyout = 0;
our @_intercepts;
our %_trace;

sub thrust {
    my ($mo, $angle, $move) = @_;
    $mo->{momx} = as_i32($mo->{momx} + fixed_mul($move, fine_cos($angle)));
    $mo->{momy} = as_i32($mo->{momy} + fixed_mul($move, fine_sin($angle)));
    return;
}

sub _trunc2 {
    my $n = as_i32($_[0]);
    return $n < 0 ? -int((-$n) / 2) : int($n / 2);
}

sub xy_move {
    my ($world, $mo, $moving) = @_;
    return if !$mo->{momx} && !$mo->{momy};
    $mo->{momx} = MAXMOVE if $mo->{momx} > MAXMOVE;
    $mo->{momx} = -MAXMOVE if $mo->{momx} < -MAXMOVE;
    $mo->{momy} = MAXMOVE if $mo->{momy} > MAXMOVE;
    $mo->{momy} = -MAXMOVE if $mo->{momy} < -MAXMOVE;
    my ($xmove, $ymove) = ($mo->{momx}, $mo->{momy});
    my $half = int(MAXMOVE / 2);
    while ($xmove || $ymove) {
        my ($ptryx, $ptryy);
        if ($xmove > $half || $ymove > $half) {
            $ptryx = as_i32($mo->{x} + _trunc2($xmove));
            $ptryy = as_i32($mo->{y} + _trunc2($ymove));
            $xmove = _trunc2($xmove);
            $ymove = _trunc2($ymove);
        }
        else {
            $ptryx = as_i32($mo->{x} + $xmove);
            $ptryy = as_i32($mo->{y} + $ymove);
            $xmove = 0;
            $ymove = 0;
        }
        if (try_move($world, $mo, $ptryx, $ptryy)) {
            next;
        }
        slide_move($world, $mo, $mo->{momx}, $mo->{momy}) if $mo->{player};
    }
    if (!$moving && abs($mo->{momx}) < STOPSPEED && abs($mo->{momy}) < STOPSPEED) {
        $mo->{momx} = 0;
        $mo->{momy} = 0;
    }
    else {
        $mo->{momx} = fixed_mul($mo->{momx}, FRICTION);
        $mo->{momy} = fixed_mul($mo->{momy}, FRICTION);
    }
    return;
}

sub point_on_line_side {
    my ($x, $y, $line) = @_;
    if ($line->{dx} == 0) {
        if ($x <= $line->{v1}{x}) {
            return $line->{dy} > 0 ? 1 : 0;
        }
        return $line->{dy} < 0 ? 1 : 0;
    }
    if ($line->{dy} == 0) {
        if ($y <= $line->{v1}{y}) {
            return $line->{dx} < 0 ? 1 : 0;
        }
        return $line->{dx} > 0 ? 1 : 0;
    }
    my $dx = as_i32($x - $line->{v1}{x});
    my $dy = as_i32($y - $line->{v1}{y});
    my $left = fixed_mul($line->{dy} >> FRACBITS, $dx);
    my $right = fixed_mul($dy, $line->{dx} >> FRACBITS);
    return $right < $left ? 0 : 1;
}

sub box_on_line_side {
    my ($bbox, $line) = @_;
    my ($p1, $p2);
    if ($line->{dx} == 0) {
        $p1 = $bbox->[BOXRIGHT] < $line->{v1}{x} ? 0 : 1;
        $p2 = $bbox->[BOXLEFT] < $line->{v1}{x} ? 0 : 1;
        if ($line->{dy} > 0) {
            $p1 ^= 1;
            $p2 ^= 1;
        }
    }
    elsif ($line->{dy} == 0) {
        $p1 = $bbox->[BOXTOP] > $line->{v1}{y} ? 0 : 1;
        $p2 = $bbox->[BOXBOTTOM] > $line->{v1}{y} ? 0 : 1;
        if ($line->{dx} < 0) {
            $p1 ^= 1;
            $p2 ^= 1;
        }
    }
    else {
        my $slope = (($line->{dy} > 0) == ($line->{dx} > 0)) ? 0 : 1;
        if ($slope == 0) {
            $p1 = point_on_line_side($bbox->[BOXLEFT], $bbox->[BOXTOP], $line);
            $p2 = point_on_line_side($bbox->[BOXRIGHT], $bbox->[BOXBOTTOM], $line);
        }
        else {
            $p1 = point_on_line_side($bbox->[BOXRIGHT], $bbox->[BOXTOP], $line);
            $p2 = point_on_line_side($bbox->[BOXLEFT], $bbox->[BOXBOTTOM], $line);
        }
    }
    return $p1 if $p1 == $p2;
    return -1;
}

sub line_opening {
    my ($line) = @_;
    return (0, 0, 0) if !$line->{backsector};
    my $front = $line->{frontsector};
    my $back = $line->{backsector};
    my $opentop = $front->{ceilingheight} < $back->{ceilingheight}
        ? $front->{ceilingheight} : $back->{ceilingheight};
    if ($front->{floorheight} > $back->{floorheight}) {
        return ($opentop, $front->{floorheight}, $back->{floorheight});
    }
    return ($opentop, $back->{floorheight}, $front->{floorheight});
}

sub unset_thing_position {
    my ($world, $thing) = @_;
    return if !$thing->{blocklinked};
    my $nxt = $thing->{bnext};
    my $prev = $thing->{bprev};
    $nxt->{bprev} = $prev if $nxt;
    if ($prev) {
        $prev->{bnext} = $nxt;
    }
    else {
        my $i = $thing->{_bindex};
        my $links = $world->{blocklinks};
        $links->[$i] = $nxt if defined $i && $i >= 0 && $i < @$links && $links->[$i] && $links->[$i] == $thing;
    }
    $thing->{bnext} = undef;
    $thing->{bprev} = undef;
    $thing->{blocklinked} = 0;
    return;
}

sub set_thing_position {
    my ($world, $thing) = @_;
    unset_thing_position($world, $thing) if $thing->{blocklinked};
    my $links = $world->{blocklinks} || [];
    $thing->{bnext} = undef;
    $thing->{bprev} = undef;
    $thing->{blocklinked} = 0;
    return if ($thing->{flags} & 16) || !@$links;
    my $bx = shar($thing->{x} - $world->{bmaporgx}, MAPBLOCKSHIFT);
    my $by = shar($thing->{y} - $world->{bmaporgy}, MAPBLOCKSHIFT);
    return if $bx < 0 || $by < 0 || $bx >= $world->{bmapwidth} || $by >= $world->{bmapheight};
    my $i = $by * $world->{bmapwidth} + $bx;
    my $head = $links->[$i];
    $thing->{bnext} = $head;
    $head->{bprev} = $thing if $head;
    $links->[$i] = $thing;
    $thing->{_bindex} = $i;
    $thing->{blocklinked} = 1;
    return;
}

sub _block_things {
    my ($world, $x, $y, $func) = @_;
    return 1 if $x < 0 || $y < 0 || $x >= $world->{bmapwidth} || $y >= $world->{bmapheight};
    my $mo = $world->{blocklinks}[$y * $world->{bmapwidth} + $x];
    while ($mo) {
        my $nxt = $mo->{bnext};
        return 0 if !$func->($mo);
        $mo = $nxt;
    }
    return 1;
}

sub _block_lines {
    my ($world, $x, $y, $func) = @_;
    return 1 if $x < 0 || $y < 0 || $x >= $world->{bmapwidth} || $y >= $world->{bmapheight};
    my $lump = $world->{blockmaplump};
    my $offset = $world->{blockmap}[$y * $world->{bmapwidth} + $x];
    while (defined $offset && $offset >= 0 && $offset < @$lump) {
        my $n = $lump->[$offset];
        $offset++;
        return 1 if $n == 0xFFFF;
        next if $n >= @{$world->{lines}};
        my $ld = $world->{lines}[$n];
        next if $ld->{validcount} == $world->{validcount};
        $ld->{validcount} = $world->{validcount};
        return 0 if !$func->($ld);
    }
    return 1;
}

sub _pit_line {
    my ($tm, $chk, $ld) = @_;
    my $bbox = $chk->{bbox};
    if ($bbox->[BOXRIGHT] <= $ld->{bbox}[BOXLEFT]
        || $bbox->[BOXLEFT] >= $ld->{bbox}[BOXRIGHT]
        || $bbox->[BOXTOP] <= $ld->{bbox}[BOXBOTTOM]
        || $bbox->[BOXBOTTOM] >= $ld->{bbox}[BOXTOP]) {
        return 1;
    }
    return 1 if box_on_line_side($bbox, $ld) != -1;
    return 0 if !$ld->{backsector};
    if (!($tm->{flags} & MF_MISSILE)) {
        return 0 if $ld->{flags} & ML_BLOCKING;
        return 0 if !$tm->{player} && ($ld->{flags} & ML_BLOCKMONSTERS);
    }
    my ($opentop, $openbottom, $lowfloor) = line_opening($ld);
    if ($opentop < $chk->{ceilingz}) {
        $chk->{ceilingz} = $opentop;
        $chk->{ceilingline} = $ld;
    }
    $chk->{floorz} = $openbottom if $openbottom > $chk->{floorz};
    $chk->{dropoffz} = $lowfloor if $lowfloor < $chk->{dropoffz};
    push @{$chk->{spechit}}, $ld if $ld->{special};
    return 1;
}

sub check_position {
    my ($world, $thing, $x, $y) = @_;
    my $chk = {
        floorz => 0, ceilingz => 0, dropoffz => 0,
        spechit => [], blocked => 0, ceilingline => undef,
        bbox => [0, 0, 0, 0],
    };
    $thing->{_tmx} = $x;
    $thing->{_tmy} = $y;
    my $radius = $thing->{radius};
    my $bbox = $chk->{bbox};
    $bbox->[BOXTOP] = $y + $radius;
    $bbox->[BOXBOTTOM] = $y - $radius;
    $bbox->[BOXRIGHT] = $x + $radius;
    $bbox->[BOXLEFT] = $x - $radius;
    my $sub = $world->point_in_subsector($x, $y);
    $chk->{floorz} = $sub->{sector}{floorheight};
    $chk->{dropoffz} = $chk->{floorz};
    $chk->{ceilingz} = $sub->{sector}{ceilingheight};
    $world->{validcount}++;
    return $chk if $thing->{flags} & MF_NOCLIP;
    my $links = $world->{blocklinks} || [];
    return $chk if !@$links;
    my ($orgx, $orgy) = ($world->{bmaporgx}, $world->{bmaporgy});
    my $xl = shar($bbox->[BOXLEFT] - $orgx - MAXRADIUS, MAPBLOCKSHIFT);
    my $xh = shar($bbox->[BOXRIGHT] - $orgx + MAXRADIUS, MAPBLOCKSHIFT);
    my $yl = shar($bbox->[BOXBOTTOM] - $orgy - MAXRADIUS, MAPBLOCKSHIFT);
    my $yh = shar($bbox->[BOXTOP] - $orgy + MAXRADIUS, MAPBLOCKSHIFT);
    for my $bx ($xl .. $xh) {
        for my $by ($yl .. $yh) {
            my $clear = _block_things($world, $bx, $by, sub {
                my $other = $_[0];
                return 1 if $other == $thing;
                if (($thing->{flags} || 0) & MF_MISSILE) {
                    return 1 if $other == $thing->{target};
                    return 1 if !($other->{flags} & MF_SHOOTABLE);
                    my $blockdist = $other->{radius} + $thing->{radius};
                    return 1 if abs($other->{x} - $x) >= $blockdist || abs($other->{y} - $y) >= $blockdist;
                    return 1 if ($thing->{z} || 0) > $other->{z} + $other->{height};
                    return 1 if ($thing->{z} || 0) + $thing->{height} < $other->{z};
                    $chk->{hitthing} = $other;
                    return 0;
                }
                my $flags = $other->{flags} || 0;
                my $special = $flags & MF_SPECIAL;
                my $solid = $flags & MF_SOLID;
                return 1 if !$special && !$solid;
                my $blockdist = ($other->{radius} || 0) + ($thing->{radius} || 0);
                return 1 if abs($other->{x} - $x) >= $blockdist || abs($other->{y} - $y) >= $blockdist;
                if ($special && $thing->{player} && $other->{alive}) {
                    Doom::Pickups::touch($world, $other, $thing);
                }
                return 1 if !$solid;
                return 0;
            });
            if (!$clear) {
                $chk->{blocked} = 1;
                return $chk;
            }
        }
    }
    $xl = shar($bbox->[BOXLEFT] - $orgx, MAPBLOCKSHIFT);
    $xh = shar($bbox->[BOXRIGHT] - $orgx, MAPBLOCKSHIFT);
    $yl = shar($bbox->[BOXBOTTOM] - $orgy, MAPBLOCKSHIFT);
    $yh = shar($bbox->[BOXTOP] - $orgy, MAPBLOCKSHIFT);
    for my $bx ($xl .. $xh) {
        for my $by ($yl .. $yh) {
            if (!_block_lines($world, $bx, $by, sub { _pit_line($thing, $chk, $_[0]) })) {
                $chk->{blocked} = 1;
                return $chk;
            }
        }
    }
    return $chk;
}

our $LAST_SPECHIT = [];

sub try_move {
    my ($world, $thing, $x, $y) = @_;
    $CEILINGLINE = undef;
    my $chk = check_position($world, $thing, $x, $y);
    $CEILINGLINE = $chk->{ceilingline};
    $LAST_SPECHIT = $chk->{spechit} || [];
    $thing->{_hitthing} = $chk->{hitthing};
    return 0 if $chk->{blocked};
    if (!($thing->{flags} & MF_NOCLIP)) {
        return 0 if $chk->{ceilingz} - $chk->{floorz} < $thing->{height};
        if (!($thing->{flags} & MF_TELEPORT) && $chk->{ceilingz} - $thing->{z} < $thing->{height}) {
            return 0;
        }
        if (!($thing->{flags} & MF_TELEPORT) && $chk->{floorz} - $thing->{z} > MAXSTEP) {
            return 0;
        }
        if (!($thing->{flags} & (MF_DROPOFF | MF_FLOAT)) && $chk->{floorz} - $chk->{dropoffz} > MAXSTEP) {
            return 0;
        }
    }
    unset_thing_position($world, $thing);
    $thing->{floorz} = $chk->{floorz};
    $thing->{ceilingz} = $chk->{ceilingz};
    $thing->{x} = $x;
    $thing->{y} = $y;
    set_thing_position($world, $thing);
    return 1;
}

sub _div {
    return { x => $_[0], y => $_[1], dx => $_[2], dy => $_[3] };
}

sub point_on_divline_side {
    my ($x, $y, $line) = @_;
    if ($line->{dx} == 0) {
        if ($x <= $line->{x}) {
            return $line->{dy} > 0 ? 1 : 0;
        }
        return $line->{dy} < 0 ? 1 : 0;
    }
    if ($line->{dy} == 0) {
        if ($y <= $line->{y}) {
            return $line->{dx} < 0 ? 1 : 0;
        }
        return $line->{dx} > 0 ? 1 : 0;
    }
    my $dx = $x - $line->{x};
    my $dy = $y - $line->{y};
    my $xor = as_u32($line->{dy}) ^ as_u32($line->{dx}) ^ as_u32($dx) ^ as_u32($dy);
    if ($xor & 0x80000000) {
        return (as_u32($line->{dy}) ^ as_u32($dx)) & 0x80000000 ? 1 : 0;
    }
    my $left = fixed_mul(shar($line->{dy}, 8), shar($dx, 8));
    my $right = fixed_mul(shar($dy, 8), shar($line->{dx}, 8));
    return $right < $left ? 0 : 1;
}

sub intercept_vector {
    my ($v2, $v1) = @_;
    my $den = as_i32(fixed_mul(shar($v1->{dy}, 8), $v2->{dx}) - fixed_mul(shar($v1->{dx}, 8), $v2->{dy}));
    return 0 if $den == 0;
    my $num = as_i32(
        fixed_mul(shar($v1->{x} - $v2->{x}, 8), $v1->{dy})
        + fixed_mul(shar($v2->{y} - $v1->{y}, 8), $v1->{dx})
    );
    return fixed_div($num, $den);
}

sub _div_trace {
    return _div($_trace{x}, $_trace{y}, $_trace{dx}, $_trace{dy});
}

sub _add_line_intercept {
    my ($ld) = @_;
    my $big = 16 * FRACUNIT;
    my ($dx, $dy) = ($_trace{dx}, $_trace{dy});
    my ($s1, $s2);
    if ($dx > $big || $dy > $big || $dx < -$big || $dy < -$big) {
        my $tr = _div_trace();
        $s1 = point_on_divline_side($ld->{v1}{x}, $ld->{v1}{y}, $tr);
        $s2 = point_on_divline_side($ld->{v2}{x}, $ld->{v2}{y}, $tr);
    }
    else {
        $s1 = point_on_line_side($_trace{x}, $_trace{y}, $ld);
        $s2 = point_on_line_side($_trace{x} + $dx, $_trace{y} + $dy, $ld);
    }
    return 1 if $s1 == $s2;
    my $frac = intercept_vector(_div_trace(), _div($ld->{v1}{x}, $ld->{v1}{y}, $ld->{dx}, $ld->{dy}));
    return 1 if $frac < 0;
    if ($_earlyout && $frac < FRACUNIT && !$ld->{backsector}) {
        return 0;
    }
    push @_intercepts, { frac => $frac, isaline => 1, line => $ld, thing => undef };
    return 1;
}

sub _add_thing_intercept {
    my ($thing) = @_;
    return 1 if !$thing || !$thing->{radius};
    my $tr = _div_trace();
    my $positive = as_i32(as_u32($tr->{dx}) ^ as_u32($tr->{dy})) > 0;
    my ($x1, $y1, $x2, $y2);
    if ($positive) {
        ($x1, $y1) = ($thing->{x} - $thing->{radius}, $thing->{y} + $thing->{radius});
        ($x2, $y2) = ($thing->{x} + $thing->{radius}, $thing->{y} - $thing->{radius});
    }
    else {
        ($x1, $y1) = ($thing->{x} - $thing->{radius}, $thing->{y} - $thing->{radius});
        ($x2, $y2) = ($thing->{x} + $thing->{radius}, $thing->{y} + $thing->{radius});
    }
    return 1 if point_on_divline_side($x1, $y1, $tr) == point_on_divline_side($x2, $y2, $tr);
    my $frac = intercept_vector($tr, _div($x1, $y1, $x2 - $x1, $y2 - $y1));
    return 1 if $frac < 0;
    push @_intercepts, { frac => $frac, isaline => 0, line => undef, thing => $thing };
    return 1;
}

sub _traverse_intercepts {
    my ($func, $maxfrac) = @_;
    my $count = @_intercepts;
    while ($count > 0) {
        $count--;
        my $dist = INT_MAX;
        my $chosen;
        for my $scan (@_intercepts) {
            if ($scan->{frac} < $dist) {
                $dist = $scan->{frac};
                $chosen = $scan;
            }
        }
        return 1 if $dist > $maxfrac;
        return 0 if !$chosen || !$func->($chosen);
        $chosen->{frac} = INT_MAX;
    }
    return 1;
}

sub _abs32 {
    my $n = as_i32($_[0]);
    return $n < 0 ? -$n : $n;
}

sub path_traverse {
    my ($world, $x1, $y1, $x2, $y2, $flags, $trav) = @_;
    $_earlyout = 0;
    $world->{validcount}++;
    @_intercepts = ();
    my ($orgx, $orgy) = ($world->{bmaporgx}, $world->{bmaporgy});
    $x1 += FRACUNIT if (($x1 - $orgx) & (MAPBLOCKSIZE - 1)) == 0;
    $y1 += FRACUNIT if (($y1 - $orgy) & (MAPBLOCKSIZE - 1)) == 0;
    $_trace{x} = $x1;
    $_trace{y} = $y1;
    $_trace{dx} = as_i32($x2 - $x1);
    $_trace{dy} = as_i32($y2 - $y1);
    $x1 = as_i32($x1 - $orgx);
    $y1 = as_i32($y1 - $orgy);
    my $xt1 = shar($x1, MAPBLOCKSHIFT);
    my $yt1 = shar($y1, MAPBLOCKSHIFT);
    my $x2m = as_i32($x2 - $orgx);
    my $y2m = as_i32($y2 - $orgy);
    my $xt2 = shar($x2m, MAPBLOCKSHIFT);
    my $yt2 = shar($y2m, MAPBLOCKSHIFT);
    my ($mapxstep, $partial, $ystep, $yintercept);
    if ($xt2 > $xt1) {
        $mapxstep = 1;
        $partial = FRACUNIT - (shar($x1, MAPBTOFRAC) & (FRACUNIT - 1));
        $ystep = fixed_div(as_i32($y2m - $y1), _abs32(as_i32($x2m - $x1)));
    }
    elsif ($xt2 < $xt1) {
        $mapxstep = -1;
        $partial = shar($x1, MAPBTOFRAC) & (FRACUNIT - 1);
        $ystep = fixed_div(as_i32($y2m - $y1), _abs32(as_i32($x2m - $x1)));
    }
    else {
        $mapxstep = 0;
        $partial = FRACUNIT;
        $ystep = 256 * FRACUNIT;
    }
    $yintercept = as_i32(shar($y1, MAPBTOFRAC) + fixed_mul($partial, $ystep));
    my ($mapystep, $xstep, $xintercept);
    if ($yt2 > $yt1) {
        $mapystep = 1;
        $partial = FRACUNIT - (shar($y1, MAPBTOFRAC) & (FRACUNIT - 1));
        $xstep = fixed_div(as_i32($x2m - $x1), _abs32(as_i32($y2m - $y1)));
    }
    elsif ($yt2 < $yt1) {
        $mapystep = -1;
        $partial = shar($y1, MAPBTOFRAC) & (FRACUNIT - 1);
        $xstep = fixed_div(as_i32($x2m - $x1), _abs32(as_i32($y2m - $y1)));
    }
    else {
        $mapystep = 0;
        $partial = FRACUNIT;
        $xstep = 256 * FRACUNIT;
    }
    $xintercept = as_i32(shar($x1, MAPBTOFRAC) + fixed_mul($partial, $xstep));
    my ($mapx, $mapy) = ($xt1, $yt1);
    for (1 .. 64) {
        if ($flags & PT_ADDLINES) {
            return 0 if !_block_lines($world, $mapx, $mapy, \&_add_line_intercept);
        }
        if ($flags & PT_ADDTHINGS) {
            return 0 if !_block_things($world, $mapx, $mapy, \&_add_thing_intercept);
        }
        last if $mapx == $xt2 && $mapy == $yt2;
        if (shar($yintercept, FRACBITS) == $mapy) {
            $yintercept = as_i32($yintercept + $ystep);
            $mapx += $mapxstep;
        }
        elsif (shar($xintercept, FRACBITS) == $mapx) {
            $xintercept = as_i32($xintercept + $xstep);
            $mapy += $mapystep;
        }
    }
    return _traverse_intercepts($trav, FRACUNIT);
}

sub _slide_blocking {
    my ($thing, $line, $frac, $best) = @_;
    my $blocking = 0;
    if (!($line->{flags} & ML_TWOSIDED)) {
        return 1 if point_on_line_side($thing->{x}, $thing->{y}, $line) != 0;
        $blocking = 1;
    }
    else {
        my ($opentop, $openbottom) = line_opening($line);
        if ($opentop - $openbottom < $thing->{height}) {
            $blocking = 1;
        }
        elsif ($opentop - $thing->{z} < $thing->{height}) {
            $blocking = 1;
        }
        elsif ($openbottom - $thing->{z} > 24 * FRACUNIT) {
            $blocking = 1;
        }
    }
    return 1 if !$blocking;
    if ($frac < $best->{frac}) {
        $best->{frac} = $frac;
        $best->{line} = $line;
    }
    return 0;
}

sub approx_distance {
    my ($dx, $dy) = (abs($_[0]), abs($_[1]));
    ($dx, $dy) = ($dy, $dx) if $dx < $dy;
    return $dx + int($dy / 2);
}

sub angle_to {
    my ($x1, $y1, $x2, $y2) = @_;
    my $x = as_i32($x2 - $x1);
    my $y = as_i32($y2 - $y1);
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

sub _hit_slide_line {
    my ($thing, $line, $tmx, $tmy) = @_;
    return ($tmx, 0) if $line->{dy} == 0;
    return (0, $tmy) if $line->{dx} == 0;
    my $side = point_on_line_side($thing->{x}, $thing->{y}, $line);
    my $lineangle = angle_to(0, 0, $line->{dx}, $line->{dy});
    $lineangle = as_u32($lineangle + ANG180) if $side == 1;
    my $moveangle = angle_to(0, 0, $tmx, $tmy);
    my $delta = as_u32($moveangle - $lineangle);
    $delta = as_u32($delta + ANG180) if $delta > ANG180;
    my $newlen = fixed_mul(approx_distance($tmx, $tmy), fine_cos($delta));
    return (fixed_mul($newlen, fine_cos($lineangle)), fixed_mul($newlen, fine_sin($lineangle)));
}

sub _stairstep {
    my ($world, $thing) = @_;
    return if try_move($world, $thing, $thing->{x}, as_i32($thing->{y} + $thing->{momy}));
    try_move($world, $thing, as_i32($thing->{x} + $thing->{momx}), $thing->{y});
    return;
}

sub slide_move {
    my ($world, $thing, $momx, $momy) = @_;
    $momx = $momx > 0 ? MAXMOVE : -MAXMOVE if abs($momx) > MAXMOVE;
    $momy = $momy > 0 ? MAXMOVE : -MAXMOVE if abs($momy) > MAXMOVE;
    $thing->{momx} = $momx;
    $thing->{momy} = $momy;
    my $hitcount = 0;
    while (1) {
        $hitcount++;
        if ($hitcount == 3) {
            _stairstep($world, $thing);
            return;
        }
        my ($leadx, $trailx, $leady, $traily);
        if ($thing->{momx} > 0) {
            $leadx = $thing->{x} + $thing->{radius};
            $trailx = $thing->{x} - $thing->{radius};
        }
        else {
            $leadx = $thing->{x} - $thing->{radius};
            $trailx = $thing->{x} + $thing->{radius};
        }
        if ($thing->{momy} > 0) {
            $leady = $thing->{y} + $thing->{radius};
            $traily = $thing->{y} - $thing->{radius};
        }
        else {
            $leady = $thing->{y} - $thing->{radius};
            $traily = $thing->{y} + $thing->{radius};
        }
        my $best = { frac => FRACUNIT + 1, line => undef };
        my $trav = sub {
            return _slide_blocking($thing, $_[0]{line}, $_[0]{frac}, $best);
        };
        my ($mx, $my) = ($thing->{momx}, $thing->{momy});
        path_traverse($world, $leadx, $leady, $leadx + $mx, $leady + $my, PT_ADDLINES, $trav);
        path_traverse($world, $trailx, $leady, $trailx + $mx, $leady + $my, PT_ADDLINES, $trav);
        path_traverse($world, $leadx, $traily, $leadx + $mx, $traily + $my, PT_ADDLINES, $trav);
        if ($best->{frac} == FRACUNIT + 1 || !$best->{line}) {
            _stairstep($world, $thing);
            return;
        }
        $best->{frac} -= 0x800;
        if ($best->{frac} > 0) {
            my $newx = fixed_mul($thing->{momx}, $best->{frac});
            my $newy = fixed_mul($thing->{momy}, $best->{frac});
            if (!try_move($world, $thing, as_i32($thing->{x} + $newx), as_i32($thing->{y} + $newy))) {
                _stairstep($world, $thing);
                return;
            }
        }
        $best->{frac} = FRACUNIT - ($best->{frac} + 0x800);
        $best->{frac} = FRACUNIT if $best->{frac} > FRACUNIT;
        return if $best->{frac} <= 0;
        my ($tmx, $tmy) = (fixed_mul($thing->{momx}, $best->{frac}), fixed_mul($thing->{momy}, $best->{frac}));
        ($tmx, $tmy) = _hit_slide_line($thing, $best->{line}, $tmx, $tmy);
        $thing->{momx} = $tmx;
        $thing->{momy} = $tmy;
        return if try_move($world, $thing, as_i32($thing->{x} + $tmx), as_i32($thing->{y} + $tmy));
    }
}

sub use_lines {
    my ($world, $mo, $specials) = @_;
    my $x1 = $mo->{x};
    my $y1 = $mo->{y};
    my $reach = shar(USERANGE, FRACBITS);
    my $x2 = $x1 + $reach * fine_cos($mo->{angle});
    my $y2 = $y1 + $reach * fine_sin($mo->{angle});
    path_traverse($world, $x1, $y1, $x2, $y2, PT_ADDLINES, sub {
        my $ln = $_[0]{line};
        if (!$ln->{special}) {
            my ($opentop, $openbottom) = line_opening($ln);
            return 0 if $opentop - $openbottom <= 0;
            return 1;
        }
        my $side = point_on_line_side($mo->{x}, $mo->{y}, $ln) == 1 ? 1 : 0;
        $specials->use_special($ln, $mo, $side) if $specials;
        return 0;
    });
    return;
}

sub thing_height_clip {
    my ($world, $thing) = @_;
    my $on_floor = $thing->{z} == $thing->{floorz};
    my $chk = check_position($world, $thing, $thing->{x}, $thing->{y});
    $thing->{floorz} = $chk->{floorz};
    $thing->{ceilingz} = $chk->{ceilingz};
    if ($on_floor) {
        $thing->{z} = $thing->{floorz};
    }
    elsif ($thing->{z} + $thing->{height} > $thing->{ceilingz}) {
        $thing->{z} = $thing->{ceilingz} - $thing->{height};
    }
    return $thing->{ceilingz} - $thing->{floorz} >= $thing->{height};
}

sub change_sector {
    my ($world, $sector, $crush) = @_;
    my $nofit = 0;
    for my $thing (@{$world->{mobjs}}) {
        next if $world->point_in_subsector($thing->{x}, $thing->{y})->{sector} != $sector;
        next if thing_height_clip($world, $thing);
        if (($thing->{health} // 1) <= 0) {
            $thing->{flags} &= ~MF_SOLID;
            $thing->{height} = 0;
            next;
        }
        next if !($thing->{flags} & MF_SHOOTABLE);
        $nofit = 1;
        if ($crush) {
            $thing->{health} -= 10;
            $thing->{flags} &= ~MF_SOLID if $thing->{health} <= 0;
            $thing->{height} = 0 if $thing->{health} <= 0;
        }
    }
    return $nofit;
}

sub _shot_point {
    my ($frac, $shootz, $slope, $range) = @_;
    my $x = $_trace{x} + fixed_mul($_trace{dx}, $frac);
    my $y = $_trace{y} + fixed_mul($_trace{dy}, $frac);
    my $z = $shootz + fixed_mul($slope, fixed_mul($frac, $range));
    return ($x, $y, $z);
}

sub _shot_ends {
    my ($source, $angle, $range) = @_;
    my $reach = shar($range, FRACBITS);
    my $x2 = $source->{x} + $reach * fine_cos($angle);
    my $y2 = $source->{y} + $reach * fine_sin($angle);
    my $shootz = $source->{z} + int($source->{height} / 2) + 8 * FRACUNIT;
    return ($x2, $y2, $shootz);
}

sub _floor2 {
    my $n = $_[0];
    return int($n / 2) if $n >= 0;
    return -int((-$n + 1) / 2);
}

sub aim_slope {
    my ($world, $source, $angle, $range) = @_;
    my ($x2, $y2, $shootz) = _shot_ends($source, $angle, $range);
    my $window = int((100 * FRACUNIT) / 160);
    my $aim = { top => $window, bottom => -$window, slope => 0, target => undef };
    my $flags = PT_ADDLINES | PT_ADDTHINGS;
    path_traverse($world, $source->{x}, $source->{y}, $x2, $y2, $flags, sub {
        my $inn = $_[0];
        if ($inn->{isaline}) {
            my $li = $inn->{line};
            return 0 if !($li->{flags} & ML_TWOSIDED);
            my ($opentop, $openbottom) = line_opening($li);
            return 0 if $openbottom >= $opentop;
            my $dist = fixed_mul($range, $inn->{frac});
            return 1 if !$dist;
            my $front = $li->{frontsector};
            my $back = $li->{backsector};
            if (!$back || $front->{floorheight} != $back->{floorheight}) {
                my $slope = fixed_div($openbottom - $shootz, $dist);
                $aim->{bottom} = $slope if $slope > $aim->{bottom};
            }
            if (!$back || $front->{ceilingheight} != $back->{ceilingheight}) {
                my $slope = fixed_div($opentop - $shootz, $dist);
                $aim->{top} = $slope if $slope < $aim->{top};
            }
            return $aim->{top} > $aim->{bottom} ? 1 : 0;
        }
        my $th = $inn->{thing};
        return 1 if !$th || $th == $source || !($th->{flags} & MF_SHOOTABLE);
        my $dist = fixed_mul($range, $inn->{frac});
        return 1 if !$dist;
        my $thingtop = fixed_div($th->{z} + $th->{height} - $shootz, $dist);
        return 1 if $thingtop < $aim->{bottom};
        my $thingbot = fixed_div($th->{z} - $shootz, $dist);
        return 1 if $thingbot > $aim->{top};
        $thingtop = $aim->{top} if $thingtop > $aim->{top};
        $thingbot = $aim->{bottom} if $thingbot < $aim->{bottom};
        $aim->{slope} = _floor2($thingtop + $thingbot);
        $aim->{target} = $th;
        return 0;
    });
    return ($aim->{slope}, $aim->{target});
}

sub line_attack {
    my ($world, $source, $angle, $range, $sky, $slope, $on_line, $on_thing) = @_;
    my ($x2, $y2, $shootz) = _shot_ends($source, $angle, $range);
    if (!defined $slope) {
        ($slope) = aim_slope($world, $source, $angle, $range);
    }
    my $flags = PT_ADDLINES | PT_ADDTHINGS;
    my $hit = 0;
    path_traverse($world, $source->{x}, $source->{y}, $x2, $y2, $flags, sub {
        my $inn = $_[0];
        if ($inn->{isaline}) {
            my $li = $inn->{line};
            my $stop = 0;
            if (!($li->{flags} & ML_TWOSIDED)) {
                $stop = 1;
            }
            else {
                my ($opentop, $openbottom) = line_opening($li);
                my $dist = fixed_mul($range, $inn->{frac});
                my $front = $li->{frontsector};
                my $back = $li->{backsector};
                if (!$dist) {
                    $stop = 1;
                }
                elsif (!$back) {
                    $stop = 1 if fixed_div($openbottom - $shootz, $dist) > $slope;
                    $stop = 1 if !$stop && fixed_div($opentop - $shootz, $dist) < $slope;
                }
                else {
                    if ($front->{floorheight} != $back->{floorheight}
                        && fixed_div($openbottom - $shootz, $dist) > $slope) {
                        $stop = 1;
                    }
                    if (!$stop && $front->{ceilingheight} != $back->{ceilingheight}
                        && fixed_div($opentop - $shootz, $dist) < $slope) {
                        $stop = 1;
                    }
                }
            }
            return 1 if !$stop;
            my $frac = $inn->{frac} - fixed_div(4 * FRACUNIT, $range);
            my ($x, $y, $z) = _shot_point($frac, $shootz, $slope, $range);
            my $front = $li->{frontsector};
            if ($front && $sky >= 0 && $front->{ceilingpic} == $sky && $z > $front->{ceilingheight}) {
                return 0 if !$li->{backsector} || $li->{backsector}{ceilingpic} == $sky;
            }
            $on_line->($li, $x, $y, $z) if $on_line;
            return 0;
        }
        my $th = $inn->{thing};
        return 1 if !$th || $th == $source || !($th->{flags} & MF_SHOOTABLE);
        my $dist = fixed_mul($range, $inn->{frac});
        return 1 if !$dist;
        return 1 if fixed_div($th->{z} + $th->{height} - $shootz, $dist) < $slope;
        return 1 if fixed_div($th->{z} - $shootz, $dist) > $slope;
        my $frac = $inn->{frac} - fixed_div(10 * FRACUNIT, $range);
        my ($x, $y, $z) = _shot_point($frac, $shootz, $slope, $range);
        $on_thing->($th, $x, $y, $z) if $on_thing;
        $hit = 1;
        return 0;
    });
    return $hit;
}

1;
