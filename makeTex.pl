#!/usr/bin/perl

=head1 NAME

makeTex.pl - a utility for creating tex files containing existing images

=head1 SYNOPSIS

makeText.pl [--out name] [--pdf] [--help] [--man] [[(--)options] file(s)] ...

=head1 DESCRIPTION

This utility makes it easy to combine a bunch of images files into a PDF.
Simply specify a list of images you would like to include in the PDF and
and this utility will create a tex document which you can then edit or
complile directly to pdf.

=head2 OPTIONS

=over 4

=item B<--out=> 

A name for the output tex file. If the name does not end in ".tex", this
extension is autocalyically appeneded. If omitted, the results are sent
to standard out. eg C<--out myfile.tex>.

=item B<--pdf>

If this flag is set, the output file is automatically send to pdflatex
to be comiled.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head3 Document Options

=over 8

=item B<--documentclass=>

This specifys the pdflatex document class. The default is "article."

=back

=head3 Inline Options

=over 8

=item B<--center>, B<--nocenter>

Will determine if images are centered or not. The default is to be centered.

=item B<--portrait>, B<--landscape>

Will allow you to display images either in portrait mode (the default) or rotated
to landscape mode.

=item B<--height=>, B<--width=>

Allows you to specify a height or width for all images in standard latex syntax, ie "5in". 
Note that only one may be set at a time, so setting height, clears out a width. Images
will therefore be scaled propotianlly. The default is to not set a height or width 
which will include images at their original size.

=item B<--section=>

Allows you to create a section header for a portion of the document

=item B<--header=>

Allows you to place a centered header on the document

=item B<--embed=>

It will include the full text of the file you specify into the body of the latex document.
This is useful including tables created with the xtable package in R.

=back 

=head2 NOTES

Note that the order of the options you specify is important. With the inline options, these
commands change how subsequent files are treated. All other commands are only executed once.

=head1 EXAMPLES

	makeTex.pl --section "Primary Results" primary*.png --section "Meta Results" meta*.png

	makeText.pl --landscape --width 10in plot1.pdf plot2.pdf

	makeText.pl --header "Final Plots" plots*.gif --out final.txt --pdf

=head1 AUTHOR

Matthew Flickinger (mflick@umich.edu)

=cut

use strict;
use warnings;

use Pod::Usage;

=begin comment
	Most of the logic is sctored in the $logic hash. Each entry
	can register for certain events and can take action. There is
	also a shared %state hash that actions can use to store settings.

	Command properties:
		options: a hash with values min: and max: that corresponts
		to the number of options that follow a particular command.
		If omitted, we assume no options follow.

		onlyonce: If set to 1, this particular command can appear 
		only once. If it occurs more than once, an error is thrown.
		If omitted, we assume a command may be repeated.

	Command events:
		init (*): This is run once for each element in the %logic hash
		so that commands can set defaults or do other initialization.
		All commands (even those not specificed at the command line)
		can recieve this event. The state object, and the command hash
		are passed as references.

		discover (**): This is run once each time a particular command is
		found in the command line. In addition to the state object
		and command hash, this method also recieved the command name
		and an array reference with the options set for this command. 
		Again, this should be used for conditional initialization.

		preamble (*): This is run once for each element in the %logic hash.
		Any return values are added to the document just before the
		\begin{document} statement. 

		postdoc (*): This is run once for each element in the %logic hash.
		Any return values are added to the document just after the
		\begin{document} statement.

		body (**): This command is run for each of the elements in the command
		line. A values returned will be placed in the document body in the
		order in which they are encounted. The function will be passed a ref
		to the state object and a ref to the command object as well as the
		command name and a ref to the options for that command.

		final (*): This is run once for each element in the %logic hash. Returned
		values are placed just before the final \end{document}

		* = once per element in logic, sig ($stateRef, $cmdRef)
		** = once per appearance in command line, sig ($stateRef, $cmdRef, $optRef)
		where $stateRef, $cmdRef are hash references, $optRef is an array ref
=cut

my %logic = (
	out => documentOptionCmd("out",""), 
	pdf => {
		init => sub {$_[0]->{"pdf"}=0},
		discover => sub {$_[0]->{"pdf"}=1},
		onlyonce => 1
	},
	documentclass => documentOptionCmd("documentclass","article"), 
	width => {
		options => nOptions(0,1),
		init => sub {$_[0]->{"width"}="";},
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			if ($optRef->[0]) {
				$stateRef->{"height"} = "";
			}
			$stateRef->{"width"} = $optRef->[0];
			return "";
		}
	},
	height => {
		options => nOptions(0,1),
		init => sub {$_[0]->{"height"}="";},
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			if ($optRef->[0]) {
				$stateRef->{"width"} = "";
			}
			$stateRef->{"height"} = $optRef->[0];
			return "";
		}
	},
	landscape => {
		init => sub {$_[0]->{"landscape"} = 0; },
		body => sub {$_[0]->{"landscape"} = 1; return "";},
		discover => sub {$_[0]->{"haslandscape"} = 1;},
		preamble => sub {
			my ($stateRef, $cmdRef) = @_;
			if ($stateRef->{"haslandscape"}) {
				return "\\usepackage{lscape}";	
			}
		}
	},
	portrait => {
		body => sub {$_[0]->{"landscape"} = 0; return "";},
	},
	center => {
		init => sub {$_[0]->{"imgcenter"}=1},
		body => sub {$_[0]->{"imgcenter"}=1; return "";}
	},
	nocenter => {
		body => sub {$_[0]->{"imgcenter"}=0, return "";}
	},
	section => {
		options => nOptions(1),
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			return "\\section{". $optRef->[0] . "}"
		}
	},
	header => {
		options => nOptions(1),
		discover => sub {$_[0]->{"hasheader"} = 1;},
		preamble => sub {
			my ($stateRef, $cmdRef) = @_;
			if ($stateRef->{"hasheader"}) {
				return "\\usepackage{fancyhdr}";	
			}
		},
		postdoc => sub {
			my ($stateRef, $cmdRef) = @_;
			if ($stateRef->{"hasheader"}) {
				return "\\pagestyle{fancy}";	
			}
		},
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			return "\\fancyhead[c]{". $optRef->[0] . "}"
		}
	},
	break => {
		body => sub {
			return "\\newpage"
		}
	},
	embed => {
		options => nOptions(1),
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			my $ret="";
			for my $f (@$optRef) {
				open(EIN, "<$f");
				while(<EIN>) {
					$ret .= $_;
				}
				close(EIN);
			}
			return $ret;
		}
	},
	file => {
		options => {min =>0, max =>999},
		body => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			for my $file (@$optRef) {
				my $ret = "\\includegraphics";
				$ret .= "[width=$stateRef->{width}]" if $stateRef->{"width"};
				$ret .= "[height=$stateRef->{height}]" if $stateRef->{"height"};
				$ret .= "{$file}";
				$ret = "\\begin{center}" . $ret . "\\end{center}" if $stateRef->{"imgcenter"};
				$ret = "\\begin{landscape}" . $ret . "\\end{landscape}" if $stateRef->{"landscape"};
				return $ret;
			}
		}
	},
	end => {
		#dummy command
	},
	help => { discover => sub{$_[0]->{"HELP"}=1} },
	man => { discover => sub{$_[0]->{"MAN"}=1} }
);

my %state= ();

my ($commandsRef, $optionsRef) = parseArguments(\@ARGV, \%logic);
initState(\%state, \%logic);
discoverState(\%state, \%logic, $commandsRef, $optionsRef);

pod2usage(-verbose => 1) if $state{"HELP"};
pod2usage(-exitstatus => 0, -verbose => 2) if $state{"MAN"};

my $outfile = $state{"out"};
if ($outfile) {
	$outfile = "$outfile.tex" if $outfile !~ m/\.tex$/;
	$outfile =~ s/\.pdf$/\.tex/;
} else {
	$outfile = "-"; #stdout
}
open(TEX, ">$outfile");

print TEX "\\documentclass{$state{documentclass}}\n";
print TEX "\\usepackage[margin=.5in]{geometry}\n";
print TEX "\\usepackage{graphicx}\n";
print TEX getPreamble(\%state, \%logic);
print TEX "\\begin{document}\n";
print TEX getPostdoc(\%state, \%logic);
print TEX getBody(\%state, \%logic, $commandsRef, $optionsRef);
print TEX getFinal(\%state, \%logic);
print TEX "\\end{document}\n";

close(TEX);

if ($state{"pdf"}) {
	if ($outfile ne "-") {
		`pdflatex -halt-on-error $outfile`;
		if ($? == -1) {
			die("could not launch pdflatex: $!, stopped");
		} else {
			my $retcode = $?>>8;
			if ($retcode!=0) {
				my $logfile = $outfile;
				$logfile =~ s/tex$/log/;
				die("pdflatex returned non-zero return code ($retcode). check $logfile for further information");
			}
		}
	} else {
		die("cannot create pdf unless you specify an --out name");
	}
}	

sub nOptions {
	my $min = shift;
	my $max = shift || $min;
	my %opt = (min => $min, max => $max);
	return \%opt;
}

sub documentOptionCmd {
	my $name = shift @_;
	my $defaultvalue = shift @_;
	my %opt = @_;
	my %cmd = (
		init => sub {
			my ($stateRef, $cmdRef) = @_;
			$stateRef->{$name} = $defaultvalue;
		},
		discover => sub {
			my ($stateRef, $cmdRef, $optRef) = @_;
			$stateRef->{$name} = $optRef->[0];
		},
		options => {min=>1, max=>1},
		onlyonce => 1
	);
	for my $o (keys %opt) {
		$cmd{$o} = $opt{$o}
	}
	return \%cmd;
}

sub parseArguments {
	my ($argRef, $logicRef) = @_;
    my $stringStarter="";
	my $string="";
    my @commands;
    my @options;
	my ($minoptcnt, $maxoptcnt, $optcnt) = (0,0,0);

	my @args = @{$argRef};
	push @args, "--end";
    while (my $arg = shift(@args)) {
		#print "processing [$arg]\n";
        if ($stringStarter) {
			# -- In the middle of a quoted string
			if ($arg =~ /$stringStarter$/) {
				chop($string);
				$string += $string;
				unshift(@args, $string);
				$stringStarter="";
			} else {
				$string += $string;
			}
        } else {
            if ($arg =~ /^-/) {
				# -- New Command
				if ($optcnt<$minoptcnt) {
					die("argument '". $commands[$#commands]. "' requires at least $minoptcnt option(s) but ".
						"only found $optcnt");
				}
				# treat commands in form --arg=val as just --arg val
				if ($arg =~ /([^=]+)=(([^=]+))/) { 
					$arg = $1;
					unshift(@args, $2);
				}
				die("command contains quote") if $arg =~ /["']/;
				$arg =~ s/^-+//;
				if (!exists $logicRef->{$arg}) {
					print STDERR "argument $arg is not recognized (known options: ", join(", ", sort keys %$logicRef), ")";

					die(", stopped");
				}
				if ($logicRef->{$arg}->{"options"}) {
					my $optc = $logicRef->{$arg}->{"options"};
					$minoptcnt = $optc->{"min"};
					$maxoptcnt = $optc->{"max"};
					$optcnt = 0;
				} else {
					($minoptcnt, $maxoptcnt, $optcnt) = (0,0,0);
				}
				push @commands, $arg;
				push @options, [];
            } else {
				# -- Command option or file name
				if ($arg =~ /^["']/) {
					# --Starting New Quoted Value
					$stringStarter = substr($arg, 0 ,1);
					$string = substr($arg, 1);	
				} else {
					if ($optcnt < $maxoptcnt) {
						#option
						push @{$options[$#options]}, $arg;
						$optcnt++;
					} else {
						#should be a file
						push @commands, "file";
						push @options, [$arg];
						($minoptcnt, $maxoptcnt, $optcnt) = (0,0,0);
					}
				}
            }
        }
    }
	my %cmdcount;
	for my $c (@commands) {
		$cmdcount{$c}++;
		if ($cmdcount{$c}>1 && $logicRef->{$c}->{"onlyone"}) {
			die("more than one '$c' found and only one is allowed, stopped");
		}
	}
	#for(my $i=0; $i<@commands; $i++) {
	#	print $commands[$i];
	#	if (@{$options[$i]}) {
	#		print ": ", join(",", @{$options[$i]});
	#	}
	#	print "\n";
	#}
	return \@commands, \@options;
}

sub initState {
	my ($stateRef, $logicRef) = @_;
	runEventsOnKnown("init", $stateRef, $logicRef);
}

sub discoverState {
	my ($stateRef, $logicRef, $cmdRef, $optRef) = @_;
	runEventsOnObserved("discover", $stateRef, $logicRef, $cmdRef, $optRef);
}

sub getPreamble {
	my ($stateRef, $logicRef) = @_;
	return runEventsOnKnown("preamble", $stateRef, $logicRef);
}

sub getPostdoc {
	my ($stateRef, $logicRef) = @_;
	return runEventsOnKnown("postdoc", $stateRef, $logicRef);
}

sub getBody {
	my ($stateRef, $logicRef, $cmdRef, $optRef) = @_;
	return runEventsOnObserved("body", $stateRef, $logicRef, $cmdRef, $optRef);
}


sub getFinal {
	my ($stateRef, $logicRef) = @_;
	return runEventsOnKnown("final", $stateRef, $logicRef);
}

sub runEventsOnKnown {
	my ($eventtype, $stateRef, $logicRef) = @_;
	my $ret ="";
	for my $cmdname (keys %$logicRef) {
		my $cmd = $logicRef->{$cmdname};
		if (exists $cmd->{$eventtype}) {
			my $val = $cmd->{$eventtype}->($stateRef, $cmd);
			$ret .= $val."\n" if $val;
		}
	}
	return $ret;
}

sub runEventsOnObserved {
	my ($eventtype, $stateRef, $logicRef, $cmdRef, $optRef) = @_;
	my $ret ="";
	for(my $i=0; $i<@$cmdRef; $i++) {
		my $cmdname = $cmdRef->[$i];
		if ($cmdname) {
			my $cmd = $logicRef->{$cmdname};
			if (exists $cmd->{$eventtype}) {
				my $val = $cmd->{$eventtype}->($stateRef, $cmd, $optRef->[$i]);
				$ret .= $val."\n" if $val;
			}
		}
	}
	return $ret;
}

