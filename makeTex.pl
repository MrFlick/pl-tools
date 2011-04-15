#!/usr/bin/perl

use strict;
use warnings;

my $landscape=0;

print <<END;
\\documentclass{article}
\\usepackage[margin=.5in]{geometry}
\\usepackage{lscape}

\\usepackage{graphicx}

\\begin{document}
\\pagestyle{empty}
END

my $secmode = 0;
my $stringopen = 0;
foreach my $token (@ARGV) {
	if ($secmode == 0 and $token ne "--sec") {
		print "\\begin{landscape}" if $landscape;
        print "\\begin{center}\n";
		#print "\\includegraphics[width=9.5in]{$token}";
		print "\\includegraphics[width=\\textwidth]{$token}";
        print "\\end{center}";
        print "\\end{landscape}\n" if $landscape;
	} else {
		if ($token eq "--sec") {
			$secmode=1;
			print "\\section{";
		} else {
			if ($stringopen==1) {
				if($token =~ /"$/) {
					$stringopen = 0;
					chop($token);
					print $token;
					$secmode=0;
				} else {
					print $token;
				}
			} else {
				if($token =~ /^"/) {
					$stringopen = 1;
					$token = substr($token,1);
					print $token;
				} else {
					print $token;
					$secmode=0;
				}
			}
			if ($secmode==0) {
				print "}\n";
			}
		}

	}
}


print <<END;
\\end{document}
END
