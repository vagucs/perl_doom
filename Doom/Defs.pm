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
# Constantes do ponto fixo e da tela. Listas do jogo continuam 0-based.

package Doom::Defs;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(
    FRACBITS FRACUNIT
    SCREENWIDTH SCREENHEIGHT SBARHEIGHT
    FINEANGLES FINEMASK ANGLETOFINESHIFT
    ANG45 ANG90 ANG180
    SLOPERANGE DBITS FIELDOFVIEW
    ML_BLOCKING ML_BLOCKMONSTERS ML_TWOSIDED ML_DONTPEGTOP ML_DONTPEGBOTTOM ML_MAPPED
    MF_SPECIAL MF_SOLID MF_SHOOTABLE MF_DROPOFF MF_PICKUP MF_NOCLIP MF_SLIDE
    MF_FLOAT MF_TELEPORT MF_MISSILE
    PLAYER_RADIUS PLAYER_HEIGHT MAXMOVE MAXSTEP MAXRADIUS
    MAPBLOCKSHIFT MAPBLOCKSIZE MAPBTOFRAC PT_ADDLINES
    FRICTION STOPSPEED
    SIL_NONE SIL_TOP SIL_BOTTOM SIL_BOTH
    LIGHTLEVELS LIGHTZSHIFT MAXLIGHTZ LIGHTSCALESHIFT MAXLIGHTSCALE
    NUMCOLORMAPS
    MAPVERTEX_SIZE MAPSEG_SIZE MAPSUBSECTOR_SIZE MAPSECTOR_SIZE
    MAPNODE_SIZE MAPTHING_SIZE MAPLINEDEF_SIZE MAPSIDEDEF_SIZE
    VIEWHEIGHT
    BOXLEFT BOXRIGHT BOXBOTTOM BOXTOP
    NF_SUBSECTOR
);

use constant FRACBITS          => 16;
use constant FRACUNIT          => 65536;
use constant SCREENWIDTH       => 320;
use constant SCREENHEIGHT      => 200;
use constant SBARHEIGHT        => 32;
use constant FINEANGLES        => 8192;
use constant FINEMASK          => 8191;
use constant ANGLETOFINESHIFT  => 19;
use constant ANG45             => 0x20000000;
use constant ANG90             => 0x40000000;
use constant ANG180            => 0x80000000;
use constant SLOPERANGE        => 2048;
use constant DBITS             => 5;
use constant FIELDOFVIEW       => 2048;
use constant ML_BLOCKING      => 1;
use constant ML_BLOCKMONSTERS => 2;
use constant ML_TWOSIDED       => 4;
use constant ML_DONTPEGTOP     => 8;
use constant ML_DONTPEGBOTTOM  => 16;
use constant ML_MAPPED         => 256;
use constant SIL_NONE          => 0;
use constant SIL_TOP           => 1;
use constant SIL_BOTTOM        => 2;
use constant SIL_BOTH          => 3;
use constant LIGHTLEVELS       => 16;
use constant LIGHTZSHIFT       => 20;
use constant MAXLIGHTZ         => 128;
use constant LIGHTSCALESHIFT   => 12;
use constant MAXLIGHTSCALE     => 48;
use constant NUMCOLORMAPS      => 32;
use constant MAPVERTEX_SIZE    => 4;
use constant MAPSEG_SIZE       => 12;
use constant MAPSUBSECTOR_SIZE => 4;
use constant MAPSECTOR_SIZE    => 26;
use constant MAPNODE_SIZE      => 28;
use constant MAPTHING_SIZE     => 10;
use constant MAPLINEDEF_SIZE   => 14;
use constant MAPSIDEDEF_SIZE   => 30;
use constant VIEWHEIGHT        => 41 * 65536;
use constant BOXLEFT           => 0;
use constant BOXRIGHT          => 1;
use constant BOXBOTTOM         => 2;
use constant BOXTOP            => 3;
use constant NF_SUBSECTOR      => 0x8000;
use constant MF_SPECIAL        => 1;
use constant MF_SOLID          => 2;
use constant MF_SHOOTABLE      => 4;
use constant MF_DROPOFF        => 0x400;
use constant MF_PICKUP         => 0x800;
use constant MF_NOCLIP         => 0x1000;
use constant MF_SLIDE          => 0x2000;
use constant MF_FLOAT          => 0x4000;
use constant MF_TELEPORT       => 0x8000;
use constant MF_MISSILE        => 0x10000;
use constant PLAYER_RADIUS     => 16 * FRACUNIT;
use constant PLAYER_HEIGHT     => 56 * FRACUNIT;
use constant MAXMOVE           => 30 * FRACUNIT;
use constant MAXSTEP           => 24 * FRACUNIT;
use constant MAXRADIUS         => 32 * FRACUNIT;
use constant MAPBLOCKSHIFT     => 23;
use constant MAPBLOCKSIZE      => 128 * FRACUNIT;
use constant MAPBTOFRAC        => 7;
use constant PT_ADDLINES       => 1;
use constant FRICTION          => 0xE800;
use constant STOPSPEED         => 0x1000;

1;
