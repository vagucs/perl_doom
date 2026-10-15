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
# Diretorio do WAD. O nome do lump tem 8 bytes e nao diferencia maiusculas.

package Doom::Wad;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        lumps => [],
        index => {},
    }, $class;
}

sub _name8 {
    my ($raw) = @_;
    $raw =~ s/\x00.*//s;
    $raw =~ s/\s+$//;
    return uc $raw;
}

sub add_file {
    my ($self, $path) = @_;
    open my $fh, '<:raw', $path or die "nao abriu $path: $!";
    my $header = '';
    read $fh, $header, 12 or die "cabecalho curto: $path";
    my ($ident, $numlumps, $infotableofs) = unpack('A4VV', $header);
    die "nao e WAD: $path" if $ident ne 'IWAD' && $ident ne 'PWAD';
    seek $fh, $infotableofs, 0 or die "diretorio: $path";
    my $directory = '';
    my $need = $numlumps * 16;
    read $fh, $directory, $need or die "diretorio curto: $path";
    close $fh;
    my $start = @{$self->{lumps}};
    for my $i (0 .. $numlumps - 1) {
        my $off = $i * 16;
        my ($pos, $size, $name) = unpack('VVa8', substr($directory, $off, 16));
        push @{$self->{lumps}}, {
            name     => _name8($name),
            position => $pos,
            size     => $size,
            wad_path => $path,
            cache    => undef,
        };
    }
    for my $i ($start .. $#{$self->{lumps}}) {
        $self->{index}{$self->{lumps}[$i]{name}} = $i;
    }
    return;
}

sub num_lumps {
    return scalar @{$_[0]{lumps}};
}

sub check_num_for_name {
    my ($self, $name) = @_;
    $name = _name8($name);
    $name = substr($name, 0, 8);
    return exists $self->{index}{$name} ? $self->{index}{$name} : -1;
}

sub get_num_for_name {
    my ($self, $name) = @_;
    my $n = $self->check_num_for_name($name);
    die "lump nao encontrado: $name" if $n < 0;
    return $n;
}

sub cache_lump_num {
    my ($self, $num) = @_;
    my $lump = $self->{lumps}[$num] or die "lump $num";
    return $lump->{cache} if defined $lump->{cache};
    open my $fh, '<:raw', $lump->{wad_path} or die $!;
    seek $fh, $lump->{position}, 0 or die $!;
    my $data = '';
    if ($lump->{size} > 0) {
        read $fh, $data, $lump->{size} or die "leitura do lump";
    }
    close $fh;
    $lump->{cache} = $data;
    return $data;
}

sub cache_lump_name {
    my ($self, $name) = @_;
    my $n = $self->check_num_for_name($name);
    die "lump nao encontrado: $name" if $n < 0;
    return $self->cache_lump_num($n);
}

sub find_iwad {
    my ($explicit) = @_;
    require File::Spec;
    require FindBin;
    if (defined $explicit && $explicit ne '') {
        die "IWAD nao encontrado: $explicit" if !-f $explicit;
        return $explicit;
    }
    my @names = qw(
        DOOM1.WAD doom1.wad DOOM.WAD doom.wad
        DOOM2.WAD doom2.wad PLUTONIA.WAD TNT.WAD
        freedoom1.wad freedoom2.wad
    );
    my @roots;
    if (my $env = $ENV{DOOMWADDIR} || $ENV{DOOMWADPATH}) {
        push @roots, $env;
    }
    my $dir;
    {
        no warnings 'once';
        $dir = $FindBin::Bin;
    }
    push @roots, (
        File::Spec->curdir,
        $dir,
    );
    push @roots, File::Spec->catdir($dir, '..');
    push @roots, File::Spec->catdir($dir, '..', '..');
    for my $root (@roots) {
        for my $name (@names) {
            my $path = File::Spec->catfile($root, $name);
            return $path if -f $path;
        }
    }
    die "Nenhum IWAD. Coloque DOOM1.WAD nesta pasta ou use -iwad arquivo.wad\n";
}

1;
