#!/usr/bin/perl -w

## per-individual plot should include
## Average-depth across all chip sites
## Individual accuracy

use strict;
use Getopt::Long;
use IO::Zlib;
use Scalar::Util qw(looks_like_number);

my $vcf1 = "";
my $vcf2 = "";
my $out = "";
my $filterFlag = 0;
my $monoFlag = 0;
my $flipFlag = 0;
my $csvExcludeIDs = "";
my $diffFlag = 0;
my $drawFlag = 0;
my $title = "";
my $orderf = "";
my $depthOrder = "";
my $makeOnly1 = 0;
my $makeOnly2 = 0;
my $makeGQ = 0;
my $makeFreq = 0;
my $makeJoint = 0;
my $minNS = 0;
my $freqCuts = ".01,.05,.15,.25";

sub uniq {my %seen; grep {! $seen{$_}++} @_};
sub posindex {map {$_[$_] => $_} 0..$#_};

my @exIDs = ();

my $result = GetOptions("vcf1=s",\$vcf1,
			"vcf2=s",\$vcf2,
			"out=s",\$out,
			"only1!", \$makeOnly1,
			"only2!", \$makeOnly2,
			"gq!", \$makeGQ,
			"freq!", \$makeFreq,
			"joint!", \$makeJoint,
			"filter",\$filterFlag,
			"mono",\$monoFlag,
			"flip",\$flipFlag,
			"exIDs=s",\$csvExcludeIDs,
			"minns=i", \$minNS,
			"draw",\$drawFlag,
			"diff",\$diffFlag,
			"title=s",\$title,
			"order=s",\$orderf,
			"depthOrder",\$depthOrder
    );

my $usage = "Usage: perl [vcfDiff.pl] --draw --diff --vcf1=[$vcf1] --vcf2=[$vcf2] --filter=[$filterFlag] --mono=[$monoFlag] --flip=[$flipFlag] --exIDs=[$csvExcludeIDs] --title=[$title] --order=[$orderf] --only1[$makeOnly1] --only2[$makeOnly2] --freq[$makeFreq] --gq[$makeGQ]\n";

unless ( ( $result ) && ( ( $drawFlag ) || ( $diffFlag ) ) ) {
    die "Error in parsing options\n$usage\n";
}

if ( ( $diffFlag ) && ( !( $vcf1 && $vcf2 && $out ) ) ) {
    die "--vcf1, --vcf2, --out option must be specified with --diff\n$usage\n";
}

if ( $diffFlag )  {
    if ( length($csvExcludeIDs) > 0 ) {
        @exIDs = split(/,/,$csvExcludeIDs);
    }
    
    my ($fh1,$ninds1,$riids1,$rhiids1) = &openVCF($vcf1);
    my ($fh2,$ninds2,$riids2,$rhiids2) = &openVCF($vcf2);
    
# build indices for overlapping individuals
    my %hExIDs = ();
    foreach my $exID (@exIDs) {
        $hExIDs{$exID} = 1;
    }
    my @idx1 = ();
    my @idx2 = ();
    for(my $i=0; $i < $ninds1; ++$i) {
        if ( ( defined($rhiids2->{$riids1->[$i]}) ) && ( !defined($hExIDs{$riids1->[$i]}) ) ) {
            push(@idx1,$rhiids1->{$riids1->[$i]});
            push(@idx2,$rhiids2->{$riids1->[$i]});
        }
    }
    
    print STDERR "Identified ".($#idx1+1)." overlapping individuals outside the exclusion list\n";
    die("no individuals to analyze, stopped") if @idx1 == 0;
    
# iterate over a hapmap SNP
    open(BOTH,">$out.both") || die "Cannot open file\n";
    open(MIS,">$out.mismatch") || die "Cannot open file\n";
    open(IND,">$out.ind") || die "Cannot open file\n";
	open(ONLY1,">$out.only1") || die "Cannot open file\n" if $makeOnly1;
	open(ONLY2,">$out.only2") || die "Cannot open file\n" if $makeOnly2;
	open(FRQ,">$out.frqs") || die "Cannot open file\n" if $makeFreq;
	open(GGQ,">$out.gqs") || die "Cannot open file\n" if $makeGQ;
	open(JNT,">$out.joint") || die "Cannot open file\n" if $makeJoint;
    
    my ($nBoth,$nMis,$nOnly1,$nOnly2) = (0,0,0,0);
    
    my @indcnts = ();
    for(my $i=0; $i < @idx1; ++$i) {
        push(@indcnts,[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
    }
	my @gqcnts = ();
	if($makeGQ) {
	    for(my $i=0; $i <= 100; ++$i) {
			push(@gqcnts,[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
		}
	}
	my @freqcnts = ();
	my $getFreqCatRef;
	if($makeFreq) {
		my @cuts = uniq(sort {$a <=> $b} split(",",$freqCuts));
		$getFreqCatRef = sub {
			my $x = shift;
			my $i=0;
			while($x>$cuts[$i]) {
				$i++;
				last if $i>=@cuts;
			}
			return $i;
		};
		for(my $i=0; $i < @cuts+1; $i++) {
			push(@freqcnts, [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
		}
	}
	my %jointcnts;
	my @jointkeys = ("ind");
	push(@jointkeys, "af","ref") if $makeFreq;
	push(@jointkeys, "gq") if $makeGQ;

    
    my ($chrom1,$pos1,$id1,$ref1,$alt1,$qual1,$filter1,$info1,$format1,$rgenos1,$rentries1);
    
    do {
	($chrom1,$pos1,$id1,$ref1,$alt1,$qual1,$filter1,$info1,$format1,$rgenos1,$rentries1) = &iterateVCF($fh1,$filterFlag);
    } while ( defined($chrom1) && ( ($chrom1 =~ /^#/ ) || ( ( $filterFlag == 1 ) && ( $filter1 ne "PASS" ) ) ) );
	      
    my ($chrom2,$pos2,$id2,$ref2,$alt2,$qual2,$filter2,$info2,$format2,$rgenos2,$rentries2) = &iterateVCF($fh2,$filterFlag,$depthOrder);
    my @genos1 = ();
    my @n1s = (0,0,0,0);
    my @n2s = (0,0,0,0);
    
    my @genos2 = ();
    my @depths2 = ();
    
    for(my $i=0; $i < @idx1; ++$i) { push(@genos1,$rgenos1->[$idx1[$i]]); ++$n1s[$genos1[$i]];}
    for(my $i=0; $i < @idx2; ++$i) { push(@genos2,$rgenos2->[$idx2[$i]]); ++$n2s[$genos2[$i]];}
    
# iterate each VCF file
    while( defined($chrom1) || defined($chrom2) ) {
        my $fbp1 = defined($chrom1) ? sprintf("%d.%09d",$chrom1,$pos1) : 100;
        my $fbp2 = defined($chrom2) ? sprintf("%d.%09d",$chrom2,$pos2) : 100;
        my ($adv1Flag, $adv2Flag) = (0,0);
        
        if ( $fbp1 eq $fbp2 ) {
            my @snpcnts = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
			my $isAltObserved = 0;
			my $freqCat=-1;
			my $refMajMin="maj";
			my %jointKey;
			my $gidx = 0;
			my $rgq2;
			
			my $ok = 1;

			if($minNS) {
				my $ns1 = getINFOvals($info1)->{"NS"};
				my $ns2 = getINFOvals($info2)->{"NS"};

				if ((defined $ns1 && $ns1<$minNS) or (defined $ns2 && $ns2<$minNS)) {
					$ok = 0;
				}
			}

			if ($ok) {
				if ($makeGQ) {
					($rgq2) = getGTvals($format2, $rentries2, "GQ");
				}
				if($makeFreq) {
					my ($af) = ($info1 =~ m/AF=([0-9.]+)/);
					if ($af) {
						if ($af>.5) {
							$af = 1-$af;
							$refMajMin = "min";
						} else {
							$refMajMin = "maj";
						}
						$freqCat = $getFreqCatRef->($af);
					}
				}
				for(my $i=0; $i < @genos1; ++$i) {
					++$snpcnts[$genos1[$i]*4+$genos2[$i]];
					$isAltObserved = 1 if $genos1[$i]>1 or $genos2[$i]>1
				}
				my $shouldFlip = 0;
				if ( ( $flipFlag == 1 ) && ( $snpcnts[5]+$snpcnts[15] < $snpcnts[7]+$snpcnts[13] ) ) {
					$shouldFlip=1;
				}
				@snpcnts = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
				for(my $i=0; $i < @genos1; ++$i) {
					if($shouldFlip) {
						if ( $genos1[$i] == 1 ) {
							$genos1[$i] = 3;
						}
						elsif ( $genos1[$i] == 3 ) {
							$genos1[$i] = 1;
						}
					}
					$gidx = $genos1[$i]*4+$genos2[$i];
					++$snpcnts[$gidx];
					++($indcnts[$i]->[$gidx]) if ( !$isAltObserved or $alt1 eq $alt2 );
					++($freqcnts[$freqCat]->[$gidx]) if ( $makeFreq and $freqCat>-1 );
					++($gqcnts[$rgq2->[$i]]->[$gidx]) if ( $makeGQ && $rgq2->[$i]>=0);
					$jointKey{"ind"} = $riids1->[$idx1[$i]] if $makeJoint;
					$jointKey{"af"} = $freqCat if $makeJoint and $makeFreq;
					$jointKey{"ref"} = $refMajMin if $makeJoint and $makeFreq;
					$jointKey{"gq"} = int($rgq2->[$i]/10) if $makeJoint and $makeGQ;
					setjoint(\%jointcnts, \%jointKey, \@jointkeys, $gidx) if $makeJoint;
				}
            
				if ( $ref1 ne $ref2 ) {
					print STDERR "Reference bases mismatch at $chrom1:$pos1 ($ref1-$ref2)\n";
				}
            
				if ( !$isAltObserved or $alt1 eq $alt2 ) {
					print BOTH "$chrom1\t$pos1\t$id1\t$ref1\t$alt1\t$qual1\t$filter1\t$info1\t".join("\t",@snpcnts)."\n";
					++$nBoth;

					if ( $#depths2 < 0 ) {
						for(my $i=0; $i < @idx2; ++$i) { push(@depths2,0); }
					}
					if ( $depthOrder ) {
						for(my $i=0; $i < @idx2; ++$i) {
						#$depths2[$i] += ($rdepth2->[$idx2[$i]]);
						}
					}
				} else {
					print MIS "$chrom1\t$pos1\t$id1\t$ref1\t$alt1-$alt2\t$qual1\t$filter1\t$info1\t".join("\t",@snpcnts)."\n";
					++$nMis;
				}
			}
            
            $adv1Flag = 1;
            $adv2Flag = 1;
        }
        ## ONLY1
        elsif ( $fbp1 < $fbp2 ) {
            ++$nOnly1;
            print ONLY1 "$chrom1\t$pos1\t$id1\t$ref1\t$alt1\t$qual1\t$filter1\t$info1\t".join("\t",@n1s)."\n" if $makeOnly1;
            $adv1Flag = 1;
        }
        ## ONLY2
        else { # fbp1 > $fbp2
            print ONLY2 "$chrom2\t$pos2\t$id2\t$ref2\t$alt2\t$qual2\t$filter2\t$info2\t".join("\t",@n2s)."\n" if $makeOnly2;
            $adv2Flag = 1;
        }
        
        if ( $adv1Flag == 1 ) {
            do {
            ($chrom1,$pos1,$id1,$ref1,$alt1,$qual1,$filter1,$info1,$format1,$rgenos1,$rentries1) = &iterateVCF($fh1,$filterFlag);
            last unless defined($chrom1);
            @n1s = (0,0,0,0);
            @genos1 = ();
            for(my $i=0; $i < @idx1; ++$i) { 
                push(@genos1,$rgenos1->[$idx1[$i]]); 
                ++$n1s[$genos1[$i]];
            }
            }
            while ( ( $monoFlag == 0 ) && ( $n1s[2]+$n1s[3] == 0 ) );
        }
        
        if ( $adv2Flag == 1 ) {
            do {
            ($chrom2,$pos2,$id2,$ref2,$alt2,$qual2,$filter2,$info2,$format2,$rgenos2,$rentries2) = &iterateVCF($fh2,$filterFlag,$depthOrder);
            last unless defined($chrom2);
            @n2s = (0,0,0,0);
            @genos2 = ();
            for(my $i=0; $i < @idx2; ++$i) { 
                push(@genos2,$rgenos2->[$idx2[$i]]); 
                ++$n2s[$genos2[$i]];
            }
            }
            while ( ( $monoFlag == 0 ) && ( $n2s[2]+$n2s[3] == 0 ) );
        }
    }
    close BOTH;
    close ONLY1 if $makeOnly1;
    close ONLY2 if $makeOnly2;
    $fh1->close();
    $fh2->close();
	
	if($makeFreq) {
		for(my $i=0; $i < @freqcnts; ++$i) {
			print FRQ "$i\t";
			print FRQ join("\t", @{$freqcnts[$i]});
			print FRQ "\n";
		}
	}
	close FRQ if $makeFreq;

	if($makeGQ) {
		for(my $i=0; $i < @gqcnts; ++$i) {
			print GGQ "$i\t";
			print GGQ join("\t", @{$gqcnts[$i]});
			print GGQ "\n";
		}

	}
	close GGQ if $makeGQ;
	
	if ($makeJoint) {
		dumpjoint(\*JNT, \%jointcnts);
	}
	close JNT if $makeJoint;
    
	for(my $i=0; $i < @indcnts; ++$i) {
		print IND $riids1->[$idx1[$i]];
		print IND "\t";
		print IND join("\t",@{$indcnts[$i]});
		print IND "\t";
		print IND sprintf("%.4lf",$depths2[$i]/$nBoth);
		print IND "\n";
	}
    close IND;
}

sub dumpjoint {
	my $fh = shift;
	my $ref = shift;
	my $col = shift || "";

	if (ref($ref) eq "HASH") {
		foreach my $key (keys(%$ref)) {
			dumpjoint($fh, $ref->{$key}, $col . "$key\t");
		}
	} else {
		print $fh $col, join("\t", @$ref), "\n";
	}
}	

sub setjoint {
	my $rcounts = shift;
	my $rvals = shift;
	my $rkeys = shift;
	my $idx = shift;

	my $ref = $rcounts;
    for(my $i=0; $i<@$rkeys; $i++) {
        if ( !$ref->{ $rvals->{$rkeys->[$i]} } ) {
            if($i<@$rkeys-1) {
                $ref->{ $rvals->{$rkeys->[$i]} } = {};
            } else {
                $ref->{ $rvals->{$rkeys->[$i]} } = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
            }
        }
        $ref = $ref->{ $rvals->{$rkeys->[$i]} }
    }
	$ref->[$idx]++;
}

if ( $drawFlag ) {
    my $prefix = $out;
    my %hCnts = ();
    my @nRefCnts = (0,0,0,0,0,0,0,0,0);
    my @nMajCnts = (0,0,0,0,0,0,0,0,0);
    my $nGenos = 0;
    
    my @orders = ();
    if ( $orderf ) {
	open(IN,$orderf) || die "Cannot open file $orderf\n";
	while(<IN>) {
	    my ($id) = split;
	    push(@orders,$id);
	}
	close IN;
    }
    
    my $nInds;
    open(IN,"$prefix.both") || die "Cannot open file\n";
    while(<IN>) {
	my ($chr,$pos,$id,$ref,$alt,$qual,$filter,$info,@n) = split;
	my $nind = $n[0]+$n[1]+$n[2]+$n[3]+$n[4]+$n[5]+$n[6]+$n[7]+$n[8]+$n[9]+$n[10]+$n[11]+$n[12]+$n[13]+$n[14]+$n[15];
	$nInds = $nind unless defined($nInds);
	my $an = 2*($n[5]+$n[6]+$n[7]+$n[9]+$n[10]+$n[11]+$n[13]+$n[14]+$n[15]);
	my $ac = $n[9]+$n[10]+$n[11]+2*($n[13]+$n[14]+$n[15]);
	#my $adjac = sprintf("%.0lf",$ac*$nind*2/$an);
	my $adjac = formatProp($ac*$nind*2,$an,"%.0lf");
	
	unless(defined($hCnts{$adjac})) {
	    $hCnts{$adjac} = [0,0,0,0,0,0,0,0,0];
	}
	my @q = (0,1,2);
	if ( $ac*2 > $an ) { @q = (2,1,0); }
	
	for(my $i=0; $i < 3; ++$i) {
	    for(my $j=0; $j < 3; ++$j) {
		$hCnts{$adjac}->[$i*3+$j] += $n[($i+1)*4+($j+1)];
		$nGenos += $n[($i+1)*4+($j+1)];
		$nRefCnts[$i*3+$j] += $n[($i+1)*4+($j+1)];
		$nMajCnts[$i*3+$j] += $n[($q[$i]+1)*4+($q[$j]+1)];
	    }
	}
    }
    close IN;
    
    open(DAT,">$prefix.AC.dat") || die "Cannot open file\n";
    my $maxFrac = 0;
    foreach my $ac (sort {$a <=> $b} keys %hCnts) {
	my @fracs = (0,0,0);
	$fracs[0] = ($hCnts{$ac}->[0]+$hCnts{$ac}->[1]+$hCnts{$ac}->[2])/($nRefCnts[0]+$nRefCnts[1]+$nRefCnts[2]+1e-6);
	$fracs[1] = ($hCnts{$ac}->[3]+$hCnts{$ac}->[4]+$hCnts{$ac}->[5])/($nRefCnts[3]+$nRefCnts[4]+$nRefCnts[5]+1e-6);
	$fracs[2] = ($hCnts{$ac}->[6]+$hCnts{$ac}->[7]+$hCnts{$ac}->[8])/($nRefCnts[6]+$nRefCnts[7]+$nRefCnts[8]+1e-6);
	foreach my $frac (@fracs) {
	    $maxFrac = $frac if ( $maxFrac < $frac );
	}
	print DAT "$ac\t".join("\t",@{$hCnts{$ac}})."\t$nGenos\n";
    }
    close DAT;
    
    open(CMD,">$prefix.AC.cmd") || die "Cannot open file\n";
    print CMD "set terminal postscript eps enhanced dashed dashlength 1.0 linewidth 1.0 size 3.5,3 font 'Calibri,12' fontfile 'calibri.pfb' fontfile 'GillSansMT.pfb' fontfile 'GillSansItalic.pfb'\n";
    print CMD "set out '$prefix.AC.eps'\n";
    print CMD "set title '$title - per AF ($nInds)' font 'GillSansMT,16'\n";
    print CMD "set xrange [0:2*$nInds]\n";
    print CMD "set yrange [0:1]\n";
    print CMD "set y2range [0:".sprintf("%.2lf",2*$maxFrac)."]\n";
    print CMD "set grid x y\n";
    print CMD "set key below box\n";
    print CMD "set xtics nomirror out\n";
    print CMD "set ytics 0,0.1 nomirror out\n";
    print CMD "set y2tics nomirror out\n";
    print CMD "set xlabel 'Non-reference allele count'\n";
    print CMD "set ylabel 'Genotype concordance'\n";
    print CMD "set y2label 'Fraction of genotypes'\n";
    my $xshift = 0.3;
    print CMD "plot '$prefix.AC.dat' u (\$1-$xshift):((\$2+\$3+\$4)/".($nRefCnts[0]+$nRefCnts[1]+$nRefCnts[2]).") lc rgbcolor 'red' lt 1 lw 1 with impulses notitle axis x1y2, '' u (\$1):((\$5+\$6+\$7)/".($nRefCnts[3]+$nRefCnts[4]+$nRefCnts[5]).") lc rgbcolor 'green' lt 1 lw 1 with impulses notitle axis x1y2, '' u (\$1+$xshift):((\$8+\$9+\$10)/".($nRefCnts[6]+$nRefCnts[7]+$nRefCnts[8]).") lc rgbcolor 'blue' lt 1 lw 1 with impulses notitle axis x1y2, '' u 1:(\$2/(\$2+\$3+\$4)) lc rgbcolor 'red' lt 1 pt 7 ps 0.5 with points title 'HomRef', '' u 1:(\$6/(\$5+\$6+\$7)) lc rgbcolor 'green' lt 1 pt 7 ps 0.5 with points title 'Het', '' u 1:(\$10/(\$8+\$9+\$10)) lc rgbcolor 'blue' lt 1 pt 7 ps 0.5 with points title 'HomAlt'\n"; 
    close CMD;
    
    my $cmd = "/net/fantasia/home/hmkang/bin/gnuplot $prefix.AC.cmd";
    #print "$cmd\n";
    #print `$cmd`;
    
    $cmd = "/net/fantasia/home/hmkang/bin/epstopdf $prefix.AC.eps";
    #print "$cmd\n";
    #print `$cmd`;
    
    open(IN,"$prefix.ind") || die "Cannot open file\n";
    open(DAT,">$prefix.ind.dat") || die "Cannot open file\n";
    my @totRights = (0,0,0);
    my @totCnts = (0,0,0);
    my %hIndDats = ();
    while(<IN>) {
	my ($indid,@n) = split;
	my $ngeno = $n[0]+$n[1]+$n[2]+$n[3]+$n[4]+$n[5]+$n[6]+$n[7]+$n[8]+$n[9]+$n[10]+$n[11]+$n[12]+$n[13]+$n[14]+$n[15];
	my $nvgeno = ($n[5]+$n[6]+$n[7]+$n[9]+$n[10]+$n[11]+$n[13]+$n[14]+$n[15]);
	my @cnts = ($n[5]+$n[6]+$n[7],$n[9]+$n[10]+$n[11],$n[13]+$n[14]+$n[15]);
	my @rights = ($n[5],$n[10],$n[15]);
	my @wrongs = ($n[6]+$n[7],$n[9]+$n[11],$n[13]+$n[14]);
	
	my $outLine = "$indid\t".join("\t",@cnts)."\t".join("\t",@rights)."\t".join("\t",@wrongs)."\t$nvgeno\t$n[16]\n";
	if ( $#orders < 0 ) {
	    print DAT $outLine;
	}
	else {
	    $hIndDats{$indid} = $outLine;
	}
	
	for(my $i=0; $i < @totRights; ++$i) {
	    $totRights[$i] += $rights[$i];
	    $totCnts[$i] += $cnts[$i];
	}
    }
    if ( $#orders >= 0 ) {
	foreach my $indid (@orders) {
	    if ( defined($hIndDats{$indid}) ) {
		print DAT $hIndDats{$indid};
	    }
	}
    }
    close DAT;
    if ( $depthOrder ) {
	my $cmd = "sort -n -k 12 $prefix.ind.dat > $prefix.ind.srt.dat";
	#print "$cmd\n";
	#print `$cmd`;
    }
    
    open(CMD,">$prefix.ind.cmd") || die "Cannot open file\n";
    my $width = sprintf("%.1lf",$nInds*0.04+1);
    print CMD "set terminal postscript eps enhanced dashed dashlength 1.0 linewidth 1.0 size $width,3 font 'Calibri,12' fontfile 'calibri.pfb' fontfile 'GillSansMT.pfb' fontfile 'GillSansItalic.pfb'\n";
    print CMD "set out '$prefix.ind.eps'\n";
    print CMD "set title '$title - per individual ($nInds)' font 'GillSansMT,16'\n";
    print CMD "set grid x y\n";
    print CMD "set key below box\n";
    print CMD "set xtics nomirror out rotate font 'Calibri,9'\n";
#print CMD "plot '$prefix.ind.dat' u (\$2/\$11):xtic(1) lc rgbcolor 'red' lt 1 lw 7 with impulses notitle axis x1y2, '' u (\$3/\$11) lc rgbcolor 'green' lt 1 lw 7 with impulses notitle axis x1y2, '' u (\$4/\$11) lc rgbcolor 'blue' lt 1 lw 7 with impulses notitle axis x1y2, '' u (\$5/\$2) lc rgbcolor 'red' pt 7 ps 0.7 with points title 'HomRef', '' u (\$6/\$3) lc rgbcolor 'green' pt 7 ps 0.7 with points title 'Het', '' u (\$7/\$4) lc rgbcolor 'blue' pt 7 ps 0.7 with points title 'HomAlt'\n"; 
    if ( $depthOrder ) {
	#print CMD "set yrange [0.6:1]\n";
	print CMD "set ylabel 'Genotype discordance'\n";
	print CMD "set y2label 'Per-sample Depth'\n";
	print CMD "set ytics 0,0.005 nomirror out\n";
	print CMD "set y2tics 0,0.2 nomirror out\n";
	print CMD "set y2range [0:*]\n";
	print CMD "set yrange [0:*]\n";
	print CMD "plot '$prefix.ind.srt.dat' u 12:xtic(1) lc rgbcolor 'black' lt 1 pt 1 ps 0.7 with points title 'Avg Sample Depth' axis x1y2, '' u (1-\$5/\$2) lc rgbcolor 'red' pt 7 ps 0.7 with points title 'HomRef', '' u (1-\$6/\$3) lc rgbcolor 'green' pt 7 ps 0.7 with points title 'Het', '' u (1-\$7/\$4) lc rgbcolor 'blue' pt 7 ps 0.7 with points title 'HomAlt'\n"; 
    }
    else {
	print CMD "set ytics 0.6,0.04 nomirror out\n";
	print CMD "set y2tics 0,0.1 nomirror out\n";
	print CMD "set ylabel 'Genotype concordance'\n";
	print CMD "set y2label 'Fraction of genotypes'\n";
	print CMD "set yrange [0.6:1]\n";
	print CMD "set y2range [0:1]\n";
	print CMD "plot '$prefix.ind.dat' u (\$2/\$11):xtic(1) lc rgbcolor 'red' lt 1 pt 6 ps 0.7 with points notitle axis x1y2, '' u (\$3/\$11) lc rgbcolor 'green' lt 1 pt 6 ps 0.7 with points notitle axis x1y2, '' u (\$4/\$11) lc rgbcolor 'blue' lt 1 pt 6 ps 0.7 with points notitle axis x1y2, '' u (\$5/\$2) lc rgbcolor 'red' pt 7 ps 0.7 with points title 'HomRef', '' u (\$6/\$3) lc rgbcolor 'green' pt 7 ps 0.7 with points title 'Het', '' u (\$7/\$4) lc rgbcolor 'blue' pt 7 ps 0.7 with points title 'HomAlt'\n"; 
    }
    close CMD;
    
    $cmd = "/net/fantasia/home/hmkang/bin/gnuplot $prefix.ind.cmd";
    #print "$cmd\n";
    #print `$cmd`;
    
    $cmd = "/net/fantasia/home/hmkang/bin/epstopdf $prefix.ind.eps";
    #print "$cmd\n";
    #print `$cmd`;

    open(OUT,">$prefix.summary") || die "Cannot open file\n";
    print OUT join("\t", "OVERALL:", arraySum(\@nRefCnts, [0,4,8]), arraySum(\@nRefCnts, [0..8]), formatArrayProp(\@nRefCnts, [0,4,8], [0..8])) . "\n";;
    print OUT join("\t", "NREF-EITHER:", arraySum(\@nRefCnts, [4,8]), arraySum(\@nRefCnts, [1..8]), formatArrayProp(\@nRefCnts, [4,8], [1..8])) . "\n";
    print OUT join("\t", "NMAJ-EITHER:", arraySum(\@nMajCnts, [4,8]), arraySum(\@nMajCnts, [1..8]), formatArrayProp(\@nMajCnts, [4,8], [1..8])) , "\n";
    print OUT "\n";
    print OUT join("\t", "HOMREF:", @nRefCnts[0..2], formatArrayProp(\@nRefCnts, 0, [0,1,2])) , "\n";
    print OUT join("\t", "HET:", @nRefCnts[3..5], formatArrayProp(\@nRefCnts, 4, [3,4,5])) , "\n";
    print OUT join("\t", "HOMALT:", @nRefCnts[6..8], formatArrayProp(\@nRefCnts, 8, [6,7,8])) , "\n";
    print OUT "\n";
    print OUT join("\t", "HOMMAJ:", @nMajCnts[0..2], formatArrayProp(\@nMajCnts, 0, [0,1,2])) , "\n";
    print OUT join("\t", "HET:", @nMajCnts[3..5], formatArrayProp(\@nMajCnts, 4, [3,4,5])) , "\n";
    print OUT join("\t", "HOMMIN:", @nMajCnts[6..8], formatArrayProp( \@nMajCnts, 8, [6,7,8])) , "\n";
}

sub arraySum {
    my $arrayRef = shift;
    my $subset = shift;
    my $sum = 0;

    if(defined($subset)) {
        if (defined(ref($subset)) && ref($subset) eq "ARRAY") {
            $sum += $_ for @$arrayRef[@$subset];
        } else {
            $sum = $arrayRef->[$subset];
        }
    } else {
        $sum += $_ for @$arrayRef;
    }

    return $sum;
}

sub formatArrayProp {
    my $arrayRef = shift;
    my $numIdx = shift;
    my $denomIdx = shift;
    my $format = shift;
    my $nan = shift;

    my $num = arraySum($arrayRef, $numIdx);
    my $denom = arraySum($arrayRef, $denomIdx);

    return formatProp($num, $denom, $format, $nan);
}

sub formatProp {
    my $num = shift;
    my $denom = shift;
    my $format = shift || "%.4lf";
    my $nan = shift || "NA";

    return ($denom != 0) ? sprintf($format, $num/$denom) : $nan;
}

sub openVCF {
    my $infile = $_[0];
    my @iids = ();
    my %hiids = ();
    my ($fbp,$a1,$a2); 

    #tie *VCF, "IO::Zlib", $infile, "rb" || die "Cannot open VCF file\n";
    my $fh;
    if ( $infile =~ /\.gz$/ ) {
	$fh = new IO::Zlib;
	$fh->open($infile,"rb") || die "Cannot open VCF file $infile\n";
    }
    else {
	$fh = new IO::File;
	$fh->open($infile,"r") || die "Cannot open VCF file $infile\n";
    }
    while(<$fh>) {
	if ( /^#CHROM/ ) {
	    my ($chrom,$pos,$id,$ref,$alt,$qual,$filter,$info,$format,@ids) = split;
	    push(@iids,@ids);
	    for(my $i=0; $i < @ids; ++$i) {
		$hiids{$ids[$i]} = $i;
	    }
	    last;
	}
	last unless ( /^#/ ); 
    }
    return($fh, $#iids+1, \@iids, \%hiids); 
}

sub getGTvals{
	my $format = shift;
	my $rentries = shift;
	my @vals = @_;
	my @r = map{[]} 0..$#vals;

	my %formatpos = posindex(split(":", $format));
	my @gts;
	foreach my $entry (@$rentries) {
		@gts = split(":",$entry);
		for(my $i=0; $i < @vals; $i++) {
			if($formatpos{$vals[$i]}) {
				push(@{$r[$i]}, $gts[$formatpos{$vals[$i]}]);
			} else {
				push(@{$r[$i]}, 0);
			}
		}
	}
	return @r;
}

sub getINFOvals {
    my $info = shift;
    my %r;
    my @vals = split(";", $info);
    foreach my $val (@vals) {
        my @p = split("=",$val,2);
        $r{$p[0]} = $p[1] || 1;
    }
    return \%r;
}


sub iterateVCF {
    my $fh = $_[0];
    my $filterFlag = defined($_[1]) ? $_[1] : 0;
    my $depthFlag = defined($_[2]) ? $_[2] : 0;
    my $line = <$fh>;
    if ( defined($line) ) {
	chomp $line;
	my ($chrom,$pos,$id,$ref,$alt,$qual,$filter,$info,$format,@entries) = split(/\s+/,$line);
	while ( ( $filterFlag > 0 ) && ($filter ne "PASS") && ( $filter ne "0" ) && ( $filter ne "\." ) ) { 
	    $line = <$fh>;
	    return unless defined($line);
	    chomp $line;
	    ($chrom,$pos,$id,$ref,$alt,$qual,$filter,$info,$format,@entries) = split(/\s+/,$line);
	}
    $chrom = 23 if $chrom eq "X";
    $chrom = 24 if $chrom eq "Y";
    $chrom = 25 if $chrom eq "XY";
    $chrom = 26 if $chrom eq "MT";
	my @genos = ();
	foreach my $entry (@entries) {
	    if ( $entry =~ /^\.[\|\/][\.\d]/ || $entry =~ /^\d[\|\/]\./) {
            push(@genos,0);
	    } else {
			if ( $entry =~ /^(\d)[\|\/](\d)/ ) {
				# ignore > 2 alleles ; treat all as alternative allele
				my $v1 = ( $1 > 1 ) ? 1 : $1;
				my $v2 = ( $2 > 1 ) ? 1 : $2;
				## 0 missing, 1 refhom, 2 het, 3 althom
				push(@genos,($v1+$v2+1)); 
			} else {
				die "Died at $chrom:$pos - @entries\n";
			}
		}
	}
	#print STDERR "@entries @genos\n";
    if( !looks_like_number($chrom) || $chrom >22) {
        undef $chrom;
    }
	return($chrom, $pos, $id, $ref, $alt, $qual, $filter, $info, $format, \@genos, \@entries); 
    }
    else {
	return;
    }
}
