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
# Estouro de 32 bits e ponto fixo 16.16, iguais a doom/compat.py.
# O inteiro do Perl 5.44 tem 8 bytes, entao o produto cabe e a mascara
# devolve os 32 bits.

package Doom::Compat;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(as_u32 as_i32 ushr shar fixed_mul fixed_div abs_fixed);

use constant MASK32 => 0xFFFFFFFF;

sub as_u32 {
    return $_[0] & MASK32;
}

sub as_i32 {
    my $n = $_[0] & MASK32;
    return $n - 4294967296 if $n >= 0x80000000;
    return $n;
}

sub ushr {
    my ($n, $bits) = @_;
    $n &= MASK32;
    return $n if $bits <= 0;
    return 0  if $bits >= 32;
    return $n >> $bits;
}

sub shar {
    my ($n, $bits) = @_;
    $n = as_i32($n);
    return $n if $bits <= 0;
    return $n < 0 ? -1 : 0 if $bits >= 31;
    # O >> do Perl preenche com zero. Num negativo isso vira um inteiro
    # enorme. A mascara devolve o deslocamento aritmetico de 32 bits,
    # igual ao >> do PHP.
    return as_i32($n >> $bits);
}

sub fixed_mul {
    # Mesma conta de as_i32((as_i32(a) * as_i32(b)) >> 16).
    # O corpo evita tres chamadas no piso, que repete esta conta
    # em cada pixel. O resultado de 32 bits continua o mesmo.
    my $a = $_[0] & MASK32;
    $a -= 4294967296 if $a >= 0x80000000;
    my $b = $_[1] & MASK32;
    $b -= 4294967296 if $b >= 0x80000000;
    my $p = ($a * $b) >> 16;
    $p &= MASK32;
    return $p - 4294967296 if $p >= 0x80000000;
    return $p;
}

sub fixed_div {
    my ($a, $b) = (as_i32($_[0]), as_i32($_[1]));
    if ($b == 0) {
        return $a >= 0 ? 0x7FFFFFFF : as_i32(-0x80000000);
    }
    my $abs_a = $a < 0 ? -$a : $a;
    my $abs_b = $b < 0 ? -$b : $b;
    if (($abs_a >> 14) >= $abs_b) {
        return ($a ^ $b) < 0 ? as_i32(-0x80000000) : 0x7FFFFFFF;
    }
    # O << do Perl, num negativo, vira inteiro sem sinal. A conta e a << 16.
    my $num = $a * 65536;
    my $q = int($num / $b);
    $q -= 1 if (($num < 0) != ($b < 0)) && ($num % $b);
    return as_i32($q);
}

sub abs_fixed {
    my $n = as_i32($_[0]);
    return $n < 0 ? -$n : $n;
}

1;
