#!/usr/bin/env perl
# Purpose
# Compares two position tables of variants with respect to TP/FP/TN/FN.

use strict;
use warnings;

use Bio::SeqIO;
use Set::Scalar;
use Getopt::Long;

# read positions file a Set::Scalar object
# format
# {
#	'header' => header_line,
# 	'positions-valid' => Set of position lines with 'valid' status
#	'positions-invalid' => Set of position lines with 'invalid' status
# }
sub read_pos
{
	my ($file) = @_;

	my %results;

	open(my $fh,"<$file") or die "Could not open $file\n";
	my $header = readline($fh);
	chomp($header);
	die "Error with header line: $header\n" if ($header !~ /^#/);
	$results{'header'} = $header;
	$results{'positions-valid'} = Set::Scalar->new;
	$results{'positions-invalid'} = Set::Scalar->new;
	$results{'positions-all'} = Set::Scalar->new;
	while(my $line = readline($fh))
	{
		chomp($line);
		my @tokens = split(/\t/,$line);

		my ($chrom,$position,$status,@bases) = @tokens;
		die "Error with line $line in $file\n" if (not defined $chrom or not defined $position or $position !~ /\d+/);
		die "Error with line $line in $file, status not properly defined\n" if (not defined $status or $status eq '');

		my $line_minus_status = join(' ',$chrom,$position,@bases);
		$results{'positions-all'}->insert($line_minus_status);
		if ($status eq 'valid') {
			$results{'positions-valid'}->insert($line_minus_status);
		} else {
			$results{'positions-invalid'}->insert($line_minus_status);
		}
	}
	close($fh);

	return \%results;
}

sub get_comparisons
{
	my ($var_true_pos,$var_detected_pos,$reference_genome_size) = @_;

	# set operations
	my $true_positives_set = $var_true_pos * $var_detected_pos;
	my $false_positives_set = $var_detected_pos - $var_true_pos;
	# See comment for true negatives below
	#my $true_negatives_set;
	my $false_negatives_set = $var_true_pos - $var_detected_pos;
	
	my $true_valid_positives = $var_true_pos->size;
	my $detected_valid_positives = $var_detected_pos->size;
	my $true_positives = $true_positives_set->size;
	my $false_positives = $false_positives_set->size;
	
	# True Negatives are positions in our alignment that have no variant in any genome 
	# That is, the number of positions in the core minus the total variant positions detected.
	# This assumes that our definition of core genome size above is valid.
	my $true_negatives = $reference_genome_size - $var_detected_pos->size;
	
	my $false_negatives = $false_negatives_set->size;
	my $accuracy = sprintf "%0.4f",($true_positives + $true_negatives) / ($true_positives + $false_positives + $true_negatives + $false_negatives);
	my $specificity = sprintf "%0.4f",($true_negatives) / ($true_negatives + $false_positives);
	my $sensitivity = sprintf "%0.4f",($true_positives) / ($true_positives + $false_negatives);
	my $precision = sprintf "%0.4f",($true_positives) / ($true_positives + $false_positives);
	my $fp_rate = sprintf "%0.4f",($false_positives) / ($true_negatives + $false_positives);
	
	return "$true_valid_positives\t$detected_valid_positives\t$true_positives\t$false_positives\t$true_negatives\t$false_negatives\t".
		"$accuracy\t$specificity\t$sensitivity\t$precision\t$fp_rate";
}

my $usage = "$0 --variants-true [variants-true.tsv] --variants-detected [variants-detected.tsv] --reference-genome [reference-genome.fasta]\n".
"Parameters:\n".
"\t--variants-true: The true variants table.\n".
"\t--variants-detected: The detected variants table\n".
"\t--reference-genome: The reference genome in fasta format.  This is used to get the length to calculate the false negative rate.\n".
"Example:\n".
"$0 --variants-true variants.tsv --variants-detected variants-detected.tsv --reference-genome reference.fasta\n\n";

my ($variants_true_file,$variants_detected_file, $reference_genome_file);

if (!GetOptions('variants-true=s' => \$variants_true_file,
		'variants-detected=s' => \$variants_detected_file,
		'reference-genome=s' => \$reference_genome_file))
{
	die "Invalid option\n".$usage;
}

die "--variants-true not defined\n$usage" if (not defined $variants_true_file);
die "--variants-detected not defined\n$usage" if (not defined $variants_detected_file);
die "--reference-genome not defined\n$usage" if (not defined $reference_genome_file);

my $reference_genome_obj = Bio::SeqIO->new(-file=>"<$reference_genome_file", -format=>"fasta");
my $reference_genome_size = 0;
while (my $seq = $reference_genome_obj->next_seq) {
	$reference_genome_size += $seq->length;
}

my $variants_true = read_pos($variants_true_file);
my $variants_detected = read_pos($variants_detected_file);

# must have same genomes and same order of genomes
if ($variants_true->{'header'} ne $variants_detected->{'header'})
{
	die "Error: headers did not match\n";
}

my $var_true_valid_pos = $variants_true->{'positions-valid'};
my $var_detected_pos = $variants_detected->{'positions-valid'};

print "Reference_Genome_File\tReference_Genome_Size\tVariants_True_File\tVariants_Detected_File\tTrue_Variants\tVariants_Detected\tTP\tFP\tTN\tFN\tAccuracy\tSpecificity\tSensitivity\tPrecision\tFP_Rate\n";
print "$reference_genome_file\t$reference_genome_size\t$variants_true_file\t$variants_detected_file\t".get_comparisons($variants_true->{'positions-valid'}, $variants_detected->{'positions-valid'}, $reference_genome_size)."\n";
