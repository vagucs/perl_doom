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
# default.cfg: mouse, mensagens, tamanho da tela e resolucao.

package Doom::Config;

use strict;
use warnings;

use File::Spec;

sub path {
    my ($dir) = @_;
    return File::Spec->catfile($dir || '.', 'default.cfg');
}

sub load {
    my ($dir) = @_;
    my %cfg = (
        mouse_sensitivity => 5,
        show_messages => 1,
        use_mouse => 1,
        screen_size => 7,
        detail => 0,
        scale => 2,
    );
    my $file = path($dir);
    open my $fh, '<', $file or return \%cfg;
    while (my $line = <$fh>) {
        next if $line !~ /\A\s*(\w+)\s+(-?\d+)/;
        $cfg{$1} = $2 + 0 if exists $cfg{$1};
    }
    close $fh;
    $cfg{mouse_sensitivity} = 0 if $cfg{mouse_sensitivity} < 0;
    $cfg{mouse_sensitivity} = 9 if $cfg{mouse_sensitivity} > 9;
    $cfg{screen_size} = 0 if $cfg{screen_size} < 0;
    $cfg{screen_size} = 8 if $cfg{screen_size} > 8;
    $cfg{scale} = 1 if $cfg{scale} < 1;
    $cfg{scale} = 6 if $cfg{scale} > 6;
    return \%cfg;
}

sub save {
    my ($dir, $cfg) = @_;
    return if !$cfg;
    open my $fh, '>', path($dir) or return;
    print $fh "mouse_sensitivity\t\t" . int($cfg->{mouse_sensitivity} || 0) . "\n";
    print $fh "show_messages\t\t" . ($cfg->{show_messages} ? 1 : 0) . "\n";
    print $fh "use_mouse\t\t" . ($cfg->{use_mouse} ? 1 : 0) . "\n";
    print $fh "screen_size\t\t" . int($cfg->{screen_size} || 0) . "\n";
    print $fh "detail\t\t" . ($cfg->{detail} ? 1 : 0) . "\n";
    print $fh "scale\t\t" . int($cfg->{scale} || 2) . "\n";
    close $fh;
    return;
}

1;
