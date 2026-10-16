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
# Titulo, depois a dificuldade, depois a vista do mapa. Setas viram e andam.
# F2 grava a partida. F3 carrega.
# A parede e as coisas solidas seguram. Espaco abre a porta.
# Ctrl dispara a pistola. O monstro anda e revida.
# Vida, municao, armadura e chave saem do chao.
# 1 pistola, 2 espingarda, 3 metralhadora, 4 lanca-foguetes, 5 plasma, 6 bfg.
# 7 serra, 8 super espingarda, 9 punho. iddqd, idkfa, idfa, idclip, idclev.
# A barra mostra vida, municao, armadura, rosto e chaves.
# No fim da fase a tela derrete e a contagem abre o mapa seguinte.
# No fim do episodio a historia aparece e uma tecla volta ao titulo.
# No episodio 3 o coelho atravessa a tela.
# No Doom 2 o desfile de monstros fecha o mapa 30.
# Um tiro acorda quem esta na sala. Tab abre o mapa.

use strict;
use warnings;
use FindBin;

$| = 1;
use lib $FindBin::Bin;

use Doom::Attack;
use Doom::Automap;
use Doom::Cheat;
use Doom::Compat qw(as_i32 as_u32 fixed_mul);
use Doom::Collision qw(set_thing_position thrust use_lines xy_move z_move);
use Doom::Finale;
use Doom::Menu;
use Doom::Save;
use Doom::Defs qw(
    ANG45 FRACUNIT VIEWHEIGHT
    MF_DROPOFF MF_NOCLIP MF_PICKUP MF_SHOOTABLE MF_SLIDE MF_SOLID
    PLAYER_HEIGHT PLAYER_RADIUS
);
use Doom::RData;
use Doom::Render;
use Doom::Sound;
use Doom::Specials;
use Doom::Status;
use Doom::Sprites qw(prepare_sprites spawn_map_things draw_sprites draw_gun);
use Doom::Tables qw(init_tables);
use Doom::VVideo qw(fill draw_patch);
use Doom::Video;
use Doom::Wad;
use Doom::Wi;
use Doom::Wipe;
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
use constant KEY_LSHIFT => 1073742049;
use constant KEY_RSHIFT => 1073742053;
use constant KEY_1 => 49;
use constant KEY_2 => 50;
use constant KEY_3 => 51;
use constant KEY_4 => 52;
use constant KEY_5 => 53;
use constant KEY_6 => 54;
use constant KEY_7 => 55;
use constant KEY_8 => 56;
use constant KEY_9 => 57;
use constant KEY_TAB => 9;
use constant KEY_MINUS => 45;
use constant KEY_EQUALS => 61;
use constant KEY_F2 => 1073741883;
use constant KEY_F3 => 1073741884;
use constant MOVE_STEP => 0x19 * 2048;
use constant MOVE_RUN => 0x32 * 2048;
use constant TURN_STEP => 640 << 16;
use constant TURN_RUN => 1280 << 16;

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
my $video = Doom::Video->new;
$video->init(2, $vsync);
print "vsync off\n" if !$vsync;
my $sound = Doom::Sound->new($wad, $video);

my $episode = 1;
my $mapn = 1;
my $skill = 2;
my $titlepic = '';
my $menu;
my $saver;
my $cheat = Doom::Cheat->new;
my $res;
my ($world, $mo, $specials, $status, $view, $x, $y, $z, $ang);

sub start_map {
    my ($carry) = @_;
    my %keep;
    if ($carry && $mo) {
        %keep = map { $_ => $mo->{$_} } qw(
            health armorpoints armortype ammo maxammo shells maxshells rockets maxrockets
            cells maxcells weapon owns_shotgun owns_chaingun owns_rocket owns_plasma owns_bfg
            owns_ssg owns_chainsaw cheats cards
            pow_invul pow_berserk pow_invis pow_suit pow_map pow_lite
        );
    }
    $world = Doom::World->new;
    $world->setup_level($wad, $res, $episode, $mapn);
    $world->{sound} = $sound;
    $sound->play_level($episode, $mapn);
    print "mapa $world->{name}\n";
    my $start = $world->player_start;
    die "sem ponto do jogador\n" if !$start;
    $x = $start->{x} * FRACUNIT;
    $y = $start->{y} * FRACUNIT;
    $ang = as_u32(int($start->{angle} * ANG45 / 45));
    my $here = $world->point_in_subsector($x, $y);
    my $floor = $here->{sector}{floorheight};
    if (!$mo) {
        $mo = {
            radius => PLAYER_RADIUS, height => PLAYER_HEIGHT,
            flags => MF_SOLID | MF_SHOOTABLE | MF_PICKUP | MF_DROPOFF | MF_SLIDE,
            player => 1, health => 100, cards => [(0) x 6],
            alive => 1, istate => 0, tics => -1, ammo => 50, maxammo => 200,
            shells => 0, maxshells => 50, rockets => 0, maxrockets => 50,
            cells => 0, maxcells => 300,
            weapon => 'pistol', owns_shotgun => 0, owns_chaingun => 0, owns_rocket => 0,
            owns_plasma => 0, owns_bfg => 0, owns_ssg => 0, owns_chainsaw => 0,
            cheats => 0, pow_invul => 0, pow_berserk => 0, pow_invis => 0,
            pow_suit => 0, pow_map => 0, pow_lite => 0,
            armorpoints => 0, armortype => 0,
            gunstate => 'ready', gunsprite => 'PISG', gunframe => 0,
            guntics => 0, gunstep => 0, refire => 0, attackdown => 0,
            flash_tics => 0, gunflash => '', gunflashframe => 0, extralight => 0,
        };
    }
    $mo->{blocklinked} = 0;
    $mo->{bnext} = undef;
    $mo->{bprev} = undef;
    $mo->{x} = $x;
    $mo->{y} = $y;
    $mo->{z} = $floor;
    $mo->{angle} = $ang;
    $mo->{floorz} = $floor;
    $mo->{ceilingz} = $here->{sector}{ceilingheight};
    $mo->{momx} = 0;
    $mo->{momy} = 0;
    $mo->{alive} = 1;
    $mo->{cards} = [(0) x 6];
    $mo->{damagecount} = 0;
    $mo->{bonuscount} = 0;
    $mo->{extralight} = 0;
    $mo->{attacker} = undef;
    $mo->{kills} = 0;
    $mo->{items} = 0;
    $mo->{secrets} = 0;
    if (!%keep) {
        $mo->{health} = 100;
        $mo->{ammo} = 50;
        $mo->{maxammo} = 200;
        $mo->{shells} = 0;
        $mo->{maxshells} = 50;
        $mo->{weapon} = 'pistol';
        $mo->{owns_shotgun} = 0;
        $mo->{owns_chaingun} = 0;
        $mo->{owns_rocket} = 0;
        $mo->{rockets} = 0;
        $mo->{maxrockets} = 50;
        $mo->{owns_plasma} = 0;
        $mo->{owns_bfg} = 0;
        $mo->{owns_ssg} = 0;
        $mo->{owns_chainsaw} = 0;
        $mo->{cells} = 0;
        $mo->{maxcells} = 300;
        $mo->{cheats} = 0;
        $mo->{pow_invul} = 0;
        $mo->{pow_berserk} = 0;
        $mo->{pow_invis} = 0;
        $mo->{pow_suit} = 0;
        $mo->{pow_map} = 0;
        $mo->{pow_lite} = 0;
        $mo->{flags} &= ~MF_NOCLIP;
        $mo->{armorpoints} = 0;
        $mo->{armortype} = 0;
        $mo->{gunstate} = 'ready';
        $mo->{wantgun} = '';
        $mo->{attackdown} = 0;
        $mo->{flash_tics} = 0;
        $mo->{refire} = 0;
        $mo->{guntics} = 0;
        Doom::Attack::_ready_pose($mo);
    }
    if (%keep) {
        $mo->{$_} = $keep{$_} for keys %keep;
        $mo->{gunstate} = 'ready';
        $mo->{wantgun} = '';
        $mo->{attackdown} = 0;
        $mo->{flash_tics} = 0;
        $mo->{refire} = 0;
        Doom::Attack::_ready_pose($mo);
    }
    set_thing_position($world, $mo);
    $world->{skill} = $skill;
    $mo->{ammo} = 100 if !%keep && $skill == 0;
    Doom::Cheat::sync_flags($mo);
    $sound->silence if $sound;
    my $things = spawn_map_things($world, $skill);
    push @{$world->{mobjs}}, $mo;
    my ($kills, $items) = (0, 0);
    for my $th (@{$world->{mobjs}}) {
        next if $th->{player};
        $kills++ if ($th->{flags} || 0) & 0x400000;
        $items++ if ($th->{flags} || 0) & 0x800000;
    }
    $world->{totalkills} = $kills;
    $world->{totalitems} = $items;
    prepare_sprites($res) if !$view;
    $specials = Doom::Specials->new($world, $res);
    $world->{specials} = $specials;
    $world->{totalsecret} = grep { ($_->{special} || 0) == 9 } @{$world->{sectors}};
    $world->{skyflat} = $res->{skyflatnum};
    $status ||= Doom::Status->new($wad);
    $status->reset($mo);
    $status->{palette} = -1;
    $status->apply_palette($video, $mo);
    $z = $mo->{z} + VIEWHEIGHT;
    $view ||= Doom::Render->new($res);
    print "coisas $things\n";
    print "balas $mo->{ammo}\n";
    return;
}

sub load_slot {
    my ($slot) = @_;
    my $data = $saver->read_save($slot);
    if (!$data) {
        print "vaga vazia\n";
        return 0;
    }
    $episode = $data->{episode} || 1;
    $mapn = $data->{mapn} || 1;
    $skill = defined $data->{skill} ? $data->{skill} : 2;
    start_map(0);
    if (!Doom::Save::restore($world, $specials, $mo, $data)) {
        print "jogo corrompido\n";
        return 0;
    }
    $x = $mo->{x};
    $y = $mo->{y};
    $ang = $mo->{angle};
    $z = $mo->{z} + VIEWHEIGHT;
    $status->reset($mo);
    $status->{palette} = -1;
    $status->apply_palette($video, $mo);
    print "jogo carregado\n";
    return 1;
}

sub warp_map {
    my ($param) = @_;
    return if !$param || $param !~ /\A(\d)(\d)\z/;
    my ($a, $b) = ($1, $2);
    my $commercial = $wad->check_num_for_name('MAP01') >= 0;
    my ($ep, $map, $lump);
    if ($commercial) {
        ($ep, $map) = (1, $a * 10 + $b);
        $lump = sprintf('MAP%02d', $map);
    }
    else {
        ($ep, $map) = ($a, $b);
        $lump = "E${ep}M$map";
    }
    if ($ep < 1 || $map < 1 || $wad->check_num_for_name($lump) < 0) {
        print "fase invalida\n";
        return;
    }
    $episode = $ep;
    $mapn = $map;
    start_map(1);
    $x = $mo->{x};
    $y = $mo->{y};
    $ang = $mo->{angle};
    $z = $mo->{z} + VIEWHEIGHT;
    $status->reset($mo) if $status;
    print "fase $lump\n";
    return;
}

sub play_cheat_music {
    my ($param) = @_;
    return if !$param || $param !~ /\A(\d)(\d)\z/;
    my ($a, $b) = ($1, $2);
    my $name;
    if ($wad->check_num_for_name('MAP01') >= 0) {
        my $map = $a * 10 + $b;
        return print "selecao impossivel\n" if $map < 1 || $map > 32;
        $name = $sound->play_level(1, $map);
        print "musica\n";
        return;
    }
    return print "selecao impossivel\n" if $a < 1 || $b < 1 || $b > 9;
    my $lump = 'D_' . uc substr("e${a}m$b", 0, 6);
    if ($wad->check_num_for_name($lump) < 0) {
        print "selecao impossivel\n";
        return;
    }
    $sound->change_music("e${a}m$b", 1);
    print "musica\n";
    return;
}

sub paint_level {
    $view->setup_frame($x, $y, $z, $ang);
    $view->{extralight} = $mo->{extralight} || 0;
    if (($mo->{pow_invul} || 0) > 128) {
        $view->{fixedcolormap} = $res->colormap(32);
    }
    elsif (($mo->{pow_lite} || 0) > 128) {
        $view->{fixedcolormap} = $res->colormap(1);
    }
    $view->render($world);
    draw_sprites($view, $world);
    draw_gun($view, $mo);
    $status->draw(\$view->{fb}, $mo);
    $status->apply_palette($video, $mo);
    return;
}

sub show_title {
    my $pic = '';
    fill(\$pic, 0);
    if ($wad->check_num_for_name('TITLEPIC') >= 0) {
        draw_patch(\$pic, 0, 0, $wad->cache_lump_name('TITLEPIC'));
    }
    $titlepic = $pic;
    $video->set_palette($pal);
    $video->upload($pic);
    $video->present;
    $sound->play_title;
    print "Enter escolhe a dificuldade. F3 carrega\n";
    while (1) {
        my $key = $video->pump;
        if ($key < 0 || $key == KEY_ESC) {
            $sound->stop_music;
            $video->shutdown;
            exit 0;
        }
        return $key if $key == KEY_ENTER || $key == KEY_KP_ENTER || $key == KEY_F3;
        $sound->update;
        $video->present;
        $video->delay(1) if !$vsync;
    }
}

sub choose_game {
    $menu ||= Doom::Menu->new($wad, $sound);
    $saver ||= Doom::Save->new($FindBin::Bin);
    while (1) {
        my $title_key = show_title();
        if ($title_key == KEY_F3) {
            my $got = $menu->pick_slot($video, $titlepic, 'load', $saver, '');
            if (!ref $got && $got && $got eq 'quit') {
                $sound->stop_music;
                $video->shutdown;
                exit 0;
            }
            return $got if ref $got eq 'HASH';
            next;
        }
        my $pick = $menu->choose($video, $titlepic);
        if (!$pick) {
            next;
        }
        if ($pick eq 'quit') {
            $sound->stop_music;
            $video->shutdown;
            exit 0;
        }
        $episode = $pick->{episode} || 1;
        $mapn = 1;
        $skill = $pick->{skill};
        my @nome = (
            'sou jovem demais', 'nem tao rude', 'me machuca bastante',
            'ultraviolencia', 'pesadelo',
        );
        print "dificuldade $nome[$skill]\n";
        return;
    }
}

my $debt = 0;
my $mode = 'level';
my $wi;
my $finale;
my $board = '';
my $wipe = Doom::Wipe->new;
my $automap = Doom::Automap->new;
my $wiping = 0;

sub begin_finale {
    my ($old, $nextmap) = @_;
    print "fim do episodio\n" if $wad->check_num_for_name('MAP01') < 0;
    $finale = Doom::Finale->new($wad, $sound, $episode, $mapn, $res);
    $finale->{nextmap} = $nextmap || 0;
    $status->{palette} = -1;
    $status->apply_palette($video, { damagecount => 0, bonuscount => 0 });
    fill(\$board, 0);
    $finale->draw(\$board);
    $wipe->capture_start($old);
    $wipe->capture_end($board);
    $wipe->begin(\$board);
    $wiping = 1;
    $mode = 'finale';
    $wi = undef;
    $debt = 0;
    return;
}

my $boot = choose_game();
init_tables();
$res = Doom::RData->new($wad);
$res->init;
my $frames = 0;
my $fps_value = 0;
my $fps_ready = 0;
my $stamp = $video->ticks;

sub note_fps {
    my ($fb) = @_;
    return if !$fps_on;
    $frames++;
    my $tick = $video->ticks;
    my $gone = ($tick - $stamp) & 0xFFFFFFFF;
    if ($stamp && $gone >= 1000) {
        $fps_value = $frames;
        $frames = 0;
        $stamp = $tick;
        $fps_ready = 1;
    }
    return if !$fps_ready || !$status || !$fb;
    $status->draw_text($fb, 250, 1, ($fps_value || 0) . ' FPS');
    return;
}
my $clock = $stamp;
my $from_title = 0;

while (1) {
    if ($from_title) {
        $boot = choose_game();
        $from_title = 0;
    }
    if ($boot && ref $boot eq 'HASH' && defined $boot->{load}) {
        start_map(0) if !load_slot($boot->{load});
    }
    else {
        start_map(0);
    }
    $boot = undef;
    $mode = 'level';
    $wi = undef;
    $finale = undef;
    $wiping = 0;
    $debt = 0;
    $clock = $video->ticks;
    my $title_back = 0;

while (1) {
    my $key = $video->pump;
    last if $key < 0;
    if ($key == KEY_ESC) {
        $title_back = 1;
        last;
    }
    if ($wiping) {
        my $now = $video->ticks;
        my $span = ($now - $clock) & 0xFFFFFFFF;
        $clock = $now;
        $debt += $span;
        my $steps = 0;
        while ($debt >= 28 && $steps < 4) {
            $debt -= 28;
            $steps++;
        }
        $debt = 28 if $debt > 28;
        my $done = $steps ? $wipe->tick($steps, \$board) : 0;
        note_fps(\$board);
        $video->upload($board);
        $sound->update;
        $video->present;
        $video->delay(1) if !$vsync;
        if ($done) {
            $wiping = 0;
            $debt = 0;
        }
        next;
    }
    if ($mode eq 'finale') {
        my $skip = $key == KEY_USE || $key == KEY_ENTER || $key == KEY_KP_ENTER
            || $key == KEY_LCTRL || $key == KEY_RCTRL;
        my $now = $video->ticks;
        my $span = ($now - $clock) & 0xFFFFFFFF;
        $clock = $now;
        $debt += $span;
        my $steps = 0;
        my $leave = 0;
        while ($debt >= 28 && $steps < 4 && $mode eq 'finale' && !$wiping) {
            $debt -= 28;
            $steps++;
            $finale->tick($skip);
            $skip = 0;
            if ($finale->{done}) {
                if ($finale->{action} eq 'worlddone') {
                    $mapn = $finale->{nextmap} || $mapn;
                    my $old = $board;
                    $mode = 'level';
                    $finale = undef;
                    start_map(1);
                    paint_level();
                    $wipe->capture_start($old);
                    $wipe->capture_end($view->{fb});
                    $wipe->begin(\$board);
                    $wiping = 1;
                    $debt = 0;
                    last;
                }
                $title_back = 1 if $finale->{action} eq 'title';
                $leave = 1;
                last;
            }
            if ($finale->{need_wipe}) {
                $finale->{need_wipe} = 0;
                my $old = $board;
                fill(\$board, 0);
                $finale->draw(\$board);
                $wipe->capture_start($old);
                $wipe->capture_end($board);
                $wipe->begin(\$board);
                $wiping = 1;
                $debt = 0;
                last;
            }
        }
        last if $leave;
        $debt = 28 if $debt > 28;
        if ($mode eq 'finale' && !$wiping) {
            fill(\$board, 0);
            $finale->draw(\$board);
            note_fps(\$board);
            $video->upload($board);
            $sound->update;
            $video->present;
            $video->delay(1) if !$vsync;
        }
        next;
    }
    if ($mode eq 'inter') {
        my $skip = $key == KEY_USE || $key == KEY_ENTER || $key == KEY_KP_ENTER
            || $key == KEY_LCTRL || $key == KEY_RCTRL;
        my $now = $video->ticks;
        my $span = ($now - $clock) & 0xFFFFFFFF;
        $clock = $now;
        $debt += $span;
        my $steps = 0;
        my $stop = 0;
        while ($debt >= 28 && $steps < 4 && $mode eq 'inter') {
            $debt -= 28;
            $steps++;
            $wi->tick($skip);
            $skip = 0;
            next if !$wi->{done};
            if (!$wi->{nextmap}) {
                print "fim do episodio\n";
                $stop = 1;
                last;
            }
            if (Doom::Finale::commercial_map($wad, $mapn, $specials->{secret})) {
                my $next = $wi->{nextmap};
                my $old = $board;
                $wi = undef;
                begin_finale($old, $next);
                last;
            }
            my $lump = $wad->check_num_for_name('MAP01') >= 0
                ? sprintf('MAP%02d', $wi->{nextmap})
                : "E${episode}M$wi->{nextmap}";
            if ($wad->check_num_for_name($lump) < 0) {
                print "fim do episodio\n";
                $stop = 1;
                last;
            }
            $mapn = $wi->{nextmap};
            $mode = 'level';
            $wi = undef;
            my $old = $board;
            start_map(1);
            paint_level();
            $wipe->capture_start($old);
            $wipe->capture_end($view->{fb});
            $wipe->begin(\$board);
            $wiping = 1;
            $debt = 0;
        }
        last if $stop;
        $debt = 28 if $debt > 28;
        if ($mode eq 'inter') {
            fill(\$board, 0);
            $wi->draw(\$board);
            note_fps(\$board);
            $video->upload($board);
            $sound->update;
            $video->present;
            $video->delay(1) if !$vsync;
        }
        next;
    }
    if ($key == KEY_F2 || $key == KEY_F3) {
        $saver ||= Doom::Save->new($FindBin::Bin);
        my $label = $wad->check_num_for_name('MAP01') >= 0
            ? sprintf('MAP%02d', $mapn) : "E${episode}M$mapn";
        my $got = $menu->pick_slot($video, $view->{fb}, $key == KEY_F2 ? 'save' : 'load', $saver, $label);
        if (!ref $got && $got && $got eq 'quit') {
            $sound->stop_music;
            $video->shutdown;
            exit 0;
        }
        if ($got && $got->{save}) {
            my $state = Doom::Save::capture($world, $specials, $episode, $mapn, $skill);
            if ($saver->write_save($got->{save}, $got->{desc}, $state)) {
                print "jogo salvo\n";
            }
            else {
                print "nao salvou\n";
            }
        }
        elsif ($got && defined $got->{load}) {
            load_slot($got->{load});
        }
        $clock = $video->ticks;
        $debt = 0;
        next;
    }
    if ($key == KEY_TAB) {
        $automap->toggle;
    }
    elsif ($automap->{active} && ($key == KEY_EQUALS || $key == 43 || $key == 1073741911)) {
        $automap->zoom_in;
    }
    elsif ($automap->{active} && ($key == KEY_MINUS || $key == 1073741910)) {
        $automap->zoom_out;
    }
    use_lines($world, $mo, $specials) if $key == KEY_USE;
    if ($specials->{exit} && !$specials->{said}) {
        $specials->{said} = 1;
        print "fim da fase\n";
        if ($wad->check_num_for_name('MAP01') < 0 && $mapn == 8 && !$specials->{secret}) {
            begin_finale($view->{fb});
            next;
        }
        $wi = Doom::Wi->new($wad, $sound, {
            episode => $episode, map => $mapn, secret => $specials->{secret} ? 1 : 0,
            kills => $mo->{kills} || 0, items => $mo->{items} || 0, secrets => $mo->{secrets} || 0,
            totalkills => $world->{totalkills} || 0, totalitems => $world->{totalitems} || 0,
            totalsecret => $world->{totalsecret} || 0, time => $specials->{time} || 0,
        });
        $status->{palette} = -1;
        $status->apply_palette($video, { damagecount => 0, bonuscount => 0 });
        fill(\$board, 0);
        $wi->draw(\$board);
        $wipe->capture_start($view->{fb});
        $wipe->capture_end($board);
        $wipe->begin(\$board);
        $wiping = 1;
        $mode = 'inter';
        $debt = 0;
        next;
    }
    Doom::Attack::switch_weapon($mo, 'pistol') if $key == KEY_1;
    Doom::Attack::switch_weapon($mo, 'shotgun') if $key == KEY_2;
    Doom::Attack::switch_weapon($mo, 'chaingun') if $key == KEY_3;
    Doom::Attack::switch_weapon($mo, 'rocket') if $key == KEY_4;
    Doom::Attack::switch_weapon($mo, 'plasma') if $key == KEY_5;
    Doom::Attack::switch_weapon($mo, 'bfg') if $key == KEY_6;
    Doom::Attack::switch_weapon($mo, 'chainsaw') if $key == KEY_7;
    Doom::Attack::switch_weapon($mo, 'ssg') if $key == KEY_8;
    Doom::Attack::switch_weapon($mo, 'fist') if $key == KEY_9;
    my $typed = $cheat->feed($key, $skill);
    if ($typed) {
        if ($typed->{act} eq 'clev') {
            warp_map($typed->{arg});
        }
        elsif ($typed->{act} eq 'mus') {
            play_cheat_music($typed->{arg});
        }
        elsif ($typed->{act} eq 'dt') {
            my $on = $automap->cycle_cheat;
            print $on ? "mapa completo\n" : "mapa normal\n" if defined $on;
        }
        else {
            Doom::Cheat::apply($mo, $typed);
            $status->tick($mo) if $status;
        }
    }
    my $now = $video->ticks;
    my $span = ($now - $clock) & 0xFFFFFFFF;
    $clock = $now;
    $debt += $span;
    my $steps = 0;
    while ($debt >= 28 && $steps < 4) {
        $debt -= 28;
        $steps++;
        Doom::Cheat::tick($mo);
        Doom::Status::decay($mo);
        $specials->tick;
        my $frozen = ($mo->{reactiontime} || 0) > 0;
        $mo->{reactiontime}-- if $frozen;
        my $run = $video->down(KEY_LSHIFT) || $video->down(KEY_RSHIFT);
        my $turn = $run ? TURN_RUN : TURN_STEP;
        my $step = $run ? MOVE_RUN : MOVE_STEP;
        if (!$frozen && $video->down(KEY_LEFT)) {
            $ang = as_u32($ang + $turn);
        }
        if (!$frozen && $video->down(KEY_RIGHT)) {
            $ang = as_u32($ang - $turn);
        }
        $mo->{angle} = $ang;
        my $ground = ($mo->{z} || 0) <= ($mo->{floorz} || 0);
        my $moving = 0;
        if (!$frozen && $ground && $video->down(KEY_UP)) {
            thrust($mo, $ang, $step);
            $moving = 1;
        }
        if (!$frozen && $ground && $video->down(KEY_DOWN)) {
            thrust($mo, $ang, -$step);
            $moving = 1;
        }
        xy_move($world, $mo, $moving);
        $ang = $mo->{angle};
        z_move($world, $mo);
        $specials->hurt_sector($mo);
        Doom::Attack::tick_mobjs($world);
        my $firing = $video->down(KEY_LCTRL) || $video->down(KEY_RCTRL);
        Doom::Attack::weapon_think($world, $mo, $firing, $res->{skyflatnum});
        $status->tick($mo);
        $x = $mo->{x};
        $y = $mo->{y};
        $z = $mo->{z} + VIEWHEIGHT;
    }
    $debt = 28 if $debt > 28;
    if ($automap->{active}) {
        fill(\$view->{fb}, 0);
        $automap->draw(\$view->{fb}, $mo, $world);
        $status->draw(\$view->{fb}, $mo);
        $status->apply_palette($video, $mo);
    }
    else {
        paint_level();
    }
    note_fps(\$view->{fb});
    $video->upload($view->{fb});
    $sound->update;
    $video->present;
    $video->delay(1) if !$vsync;
    }
    last if !$title_back;
    $from_title = 1;
}

$sound->stop_music;
$video->shutdown;
exit 0;
