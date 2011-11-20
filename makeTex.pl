#!/usr/bin/perl

use strict;
use warnings;

my $landscape=0;
my $width="";
my $height="";

open(TEX, ">-");

print TEX <<END;
\\documentclass{article}
\\usepackage[margin=.5in]{geometry}
\\usepackage{lscape}
\\usepackage{fancyhdr}

\\usepackage{graphicx}

\\begin{document}
\\pagestyle{fancy}
END

my $secmode = 0;
my $widthmode = 0;
my $stringopen = 0;
foreach my $token (@ARGV) {
	if ($secmode == 0 and $widthmode ==0 and 
        $token ne "--sec" and $token ne "--title" 
        and $token ne "--landscape" and $token ne "--portrait"
        and $token ne "--width" and $token ne "--height") {

        print TEX "\\begin{landscape}" if $landscape;
        print TEX "\\begin{center}\n";
        print TEX "\\includegraphics";
        print TEX "[width=$width]" if $width;
        print TEX "[height=$height]" if $height;
        print TEX "{$token}";
        print TEX "\\end{center}";
        print TEX "\\end{landscape}\n" if $landscape;
    } elsif ($widthmode==1) {
        $width = $token;
        $height="";
        $widthmode=0;
    } elsif ($widthmode==2) {
        $height = $token;
        $width="";
        $widthmode=0;
	} else {
		if ($token eq "--sec") {
			$secmode=1;
			print TEX "\\section{";
        } elsif ($token eq "--title") { 
            $secmode=1;
            print TEX "\\fancyhead[C]{";
        } elsif ($token eq "--landscape") {
            $landscape=1;
        } elsif ($token eq "--portrait") {
            $landscape=0;
        } elsif ($token eq "--width") {
            $widthmode = 1;
        } elsif ($token eq "--height") {
            $widthmode = 2;
		} else {
			if ($stringopen==1) {
				if($token =~ /"$/) {
					$stringopen = 0;
					chop($token);
					print TEX $token;
					$secmode=0;
				} else {
					print TEX $token;
				}
			} else {
				if($token =~ /^"/) {
					$stringopen = 1;
					$token = substr($token,1);
					print TEX $token;
				} else {
					print TEX $token;
					$secmode=0;
				}
			}
			if ($secmode==0) {
				print TEX "}\n";
			}
		}

	}
}


print TEX <<END;
\\end{document}
END

sub parseArguments {
    my $string;
    my @commands;
    my @options;
    my %settings;

    foreach my $t (@_) {
        if ($string) {

        } else {
            if ($t = m/^-/) {
                push @commands, "$t";
                push @options, [];
            } else {
                push @{$options[$#options]}, $t;
            }
        }
    }
}
