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
# Titulo, depois a vista do E1M1. Setas viram e andam.
# A parede e as coisas solidas seguram. Espaco abre a porta.
# Ctrl dispara a pistola. O monstro anda e revida.
# Vida, municao, armadura e chave saem do chao.

use strict;
use warnings;
use FindBin;

$| = 1;
use lib $FindBin::Bin;

use Doom::Attack;
use Doom::Compat qw(as_i32 as_u32 fixed_mul);
use Doom::Collision qw(set_thing_position thrust use_lines xy_move);
use Doom::Defs qw(
    ANG45 FRACUNIT VIEWHEIGHT
    MF_DROPOFF MF_PICKUP MF_SHOOTABLE MF_SLIDE MF_SOLID
    PLAYER_HEIGHT PLAYER_RADIUS
);
use Doom::RData;
use Doom::Render;
use Doom::Specials;
use Doom::Sprites qw(prepare_sprites spawn_map_things draw_sprites draw_gun);
use Doom::Tables qw(init_tables);
use Doom::VVideo qw(fill draw_patch);
use Doom::Video;
use Doom::Wad;
use Doom::World;

use constant KEY_ESC   => 27;
use constant KEY_ENTER => 13;
use constant KEY_KP_ENTER => 1073741912;
use constant KEY_LEFT  => 1073741904;
use constant KEY_RIGHT => 1073741903;
use constant KEY_DOWN  => 1073741905;
use constant KEY_UP    => 1073741906;
use constant KEY_USE   => 32;
use constant KEY_LCTRL => 1073742048;
use constant KEY_RCTRL => 1073742052;
use constant MOVE_STEP => 0x19 * 2048;
use constant TURN_STEP => 640 << 16;

my $want = '';
my $fps_on = 0;
my $vsync = 1;
for (my $i = 0; $i < @ARGV; $i++) {
    my $arg = $ARGV[$i];
    if (lc($arg) eq '-fps') {
        $fps_on = 1;
    }
    elsif (lc($arg) eq '-novsync') {
        $vsync = 0;
    }
    elsif (lc($arg) eq '-iwad') {
        $want = $ARGV[++$i] // '';
    }
    elsif ($arg =~ /\.wad\z/i) {
        $want = $arg;
    }
}

my $prod = fixed_mul(65536, 196608);
die "ponto fixo $prod\n" if $prod != 196608;
my $neg = as_i32(-1);
die "estouro $neg\n" if $neg != -1;

my $path = Doom::Wad::find_iwad($want);
my $wad = Doom::Wad->new;
$wad->add_file($path);
print "IWAD $path  lumps " . $wad->num_lumps . "\n";

my $pal = $wad->cache_lump_name('PLAYPAL');
my $fb = '';
fill(\$fb, 0);
if ($wad->check_num_for_name('TITLEPIC') >= 0) {
    draw_patch(\$fb, 0, 0, $wad->cache_lump_name('TITLEPIC'));
}

my $video = Doom::Video->new;
$video->init(2, $vsync);
print "vsync off\n" if !$vsync;
$video->set_palette($pal);
$video->upload($fb);
$video->present;
print "Enter entra no mapa\n";

while (1) {
    my $key = $video->pump;
    if ($key < 0 || $key == KEY_ESC) {
        $video->shutdown;
        exit 0;
    }
    last if $key == KEY_ENTER || $key == KEY_KP_ENTER;
    $video->present;
    $video->delay(1) if !$vsync;
}

init_tables();
my $res = Doom::RData->new($wad);
$res->init;
my $world = Doom::World->new;
$world->setup_level($wad, $res, 1, 1);
print "mapa $world->{name}\n";

my $start = $world->player_start;
die "sem ponto do jogador\n" if !$start;
my $x = $start->{x} * FRACUNIT;
my $y = $start->{y} * FRACUNIT;
my $ang = as_u32(int($start->{angle} * ANG45 / 45));
my $here = $world->point_in_subsector($x, $y);
my $floor = $here->{sector}{floorheight};
my $mo = {
    x => $x, y => $y, z => $floor, angle => $ang,
    radius => PLAYER_RADIUS, height => PLAYER_HEIGHT,
    floorz => $floor, ceilingz => $here->{sector}{ceilingheight},
    flags => MF_SOLID | MF_SHOOTABLE | MF_PICKUP | MF_DROPOFF | MF_SLIDE,
    player => 1, health => 100, cards => [(0) x 6], momx => 0, momy => 0,
    alive => 1, istate => 0, tics => -1, ammo => 50, maxammo => 200,
    armorpoints => 0, armortype => 0,
    gunstate => 'ready', gunsprite => 'PISG', gunframe => 0,
    guntics => 0, gunstep => 0, refire => 0, attackdown => 0,
    flash_tics => 0, gunflash => '', gunflashframe => 0, extralight => 0,
};
set_thing_position($world, $mo);
my $things = spawn_map_things($world, 2);
push @{$world->{mobjs}}, $mo;
prepare_sprites($res);
print "coisas $things\n";
print "balas $mo->{ammo}\n";
my $specials = Doom::Specials->new($world);
$world->{specials} = $specials;
$world->{skyflat} = $res->{skyflatnum};
my $z = $mo->{z} + VIEWHEIGHT;

my $view = Doom::Render->new($res);
my $frames = 0;
my $stamp = $video->ticks;
my $clock = $stamp;
my $debt = 0;

while (1) {
    my $key = $video->pump;
    last if $key < 0 || $key == KEY_ESC;
    use_lines($world, $mo, $specials) if $key == KEY_USE;
    my $now = $video->ticks;
    my $span = ($now - $clock) & 0xFFFFFFFF;
    $clock = $now;
    $debt += $span;
    my $steps = 0;
    while ($debt >= 28 && $steps < 4) {
        $debt -= 28;
        $steps++;
        $specials->tick;
        if ($video->down(KEY_LEFT)) {
            $ang = as_u32($ang + TURN_STEP);
        }
        if ($video->down(KEY_RIGHT)) {
            $ang = as_u32($ang - TURN_STEP);
        }
        $mo->{angle} = $ang;
        my $moving = 0;
        if ($video->down(KEY_UP)) {
            thrust($mo, $ang, MOVE_STEP);
            $moving = 1;
        }
        if ($video->down(KEY_DOWN)) {
            thrust($mo, $ang, -MOVE_STEP);
            $moving = 1;
        }
        xy_move($world, $mo, $moving);
        $mo->{z} = $mo->{floorz};
        Doom::Attack::tick_mobjs($world);
        my $firing = $video->down(KEY_LCTRL) || $video->down(KEY_RCTRL);
        Doom::Attack::weapon_think($world, $mo, $firing, $res->{skyflatnum});
        $x = $mo->{x};
        $y = $mo->{y};
        $z = $mo->{z} + VIEWHEIGHT;
    }
    $debt = 28 if $debt > 28;
    $view->setup_frame($x, $y, $z, $ang);
    $view->{extralight} = $mo->{extralight} || 0;
    $view->render($world);
    draw_sprites($view, $world);
    draw_gun($view, $mo);
    $video->upload($view->{fb});
    $video->present;
    $frames++;
    if ($fps_on) {
        my $tick = $video->ticks;
        my $gone = ($tick - $stamp) & 0xFFFFFFFF;
        if ($stamp && $gone >= 1000) {
            print "fps $frames\n";
            $frames = 0;
            $stamp = $tick;
        }
    }
    $video->delay(1) if !$vsync;
}

$video->shutdown;
exit 0;
