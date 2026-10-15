use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;

use Doom::Attack;
use Doom::Collision qw(set_thing_position try_move);
use Doom::Defs qw(FRACUNIT MF_DROPOFF MF_PICKUP MF_SHOOTABLE MF_SLIDE MF_SOLID PLAYER_HEIGHT PLAYER_RADIUS);
use Doom::RData;
use Doom::Sprites qw(spawn_map_things);
use Doom::Tables qw(init_tables);
use Doom::Wad;
use Doom::World;

init_tables();
my $wad = Doom::Wad->new;
$wad->add_file(Doom::Wad::find_iwad(''));
my $res = Doom::RData->new($wad);
$res->init;
my $world = Doom::World->new;
$world->setup_level($wad, $res, 1, 1);
spawn_map_things($world, 2);

my $mo = {
    x => 0, y => 0, z => 0, angle => 0,
    radius => PLAYER_RADIUS, height => PLAYER_HEIGHT,
    floorz => 0, ceilingz => 0,
    flags => MF_SOLID | MF_SHOOTABLE | MF_PICKUP | MF_DROPOFF | MF_SLIDE,
    player => 1, health => 40, cards => [(0) x 6], alive => 1,
    ammo => 50, maxammo => 200, armorpoints => 0, armortype => 0,
    istate => 0, tics => -1,
};
push @{$world->{mobjs}}, $mo;

my ($stim, $key, $clip, $arm);
for my $th (@{$world->{mobjs}}) {
    my $n = $th->{doomednum} || 0;
    $stim = $th if !$stim && $n == 2011;
    $key = $th if !$key && $n == 5;
    $clip = $th if !$clip && $n == 2007;
    $arm = $th if !$arm && $n == 2018;
}
die "sem estimulante\n" if !$stim;
if (!$key) {
    $key = {
        x => $stim->{x} + 80 * FRACUNIT, y => $stim->{y}, z => $stim->{z},
        radius => 20 * FRACUNIT, height => 16 * FRACUNIT,
        flags => 1, alive => 1, doomednum => 5, player => undef,
        sprite => 'BKEY', frame => 0,
    };
    push @{$world->{mobjs}}, $key;
    set_thing_position($world, $key);
}

sub _stand {
    my ($item) = @_;
    $mo->{x} = $item->{x};
    $mo->{y} = $item->{y};
    $mo->{z} = $item->{z};
    set_thing_position($world, $mo);
    try_move($world, $mo, $mo->{x} + FRACUNIT, $mo->{y});
}

_stand($stim);
my $after_stim = $mo->{health};
my $stim_gone = $stim->{alive} ? 0 : 1;
print "stim vida $after_stim some $stim_gone\n";

_stand($key);
my $key_gone = $key->{alive} ? 0 : 1;
print "chave $mo->{cards}[0] some $key_gone\n";

if ($clip) {
    my $before = $mo->{ammo};
    _stand($clip);
    print "pente $before -> $mo->{ammo} some " . ($clip->{alive} ? 0 : 1) . "\n";
}
if ($arm) {
    _stand($arm);
    my $hp = $mo->{health};
    Doom::Attack::damage_mobj($world, $mo, $mo, 30);
    print "armadura $mo->{armorpoints} tipo $mo->{armortype} vida $hp -> $mo->{health}\n";
}

my $ok = $after_stim == 50 && $mo->{cards}[0] && $stim_gone && $key_gone;
exit($ok ? 0 : 1);
