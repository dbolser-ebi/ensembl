use lib 't';
use strict;
use warnings;


BEGIN { $| = 1;  
	use Test;
	plan tests => 59;
}

use MultiTestDB;
use Bio::EnsEMBL::DBSQL::SliceAdaptor;
use Bio::EnsEMBL::Slice;
use TestUtils qw(test_getter_setter debug);

our $verbose = 0;

my ($CHR, $START, $END, $FLANKING) = ("20", 30_252_000, 31_252_001, 1000);

#
# slice adaptor compiles
#
ok(1);

my $multi = MultiTestDB->new;
my $db    = $multi->get_DBAdaptor('core');


#
# SliceAdaptor::new
#
my $slice_adaptor = Bio::EnsEMBL::DBSQL::SliceAdaptor->new($db->_obj);
ok($slice_adaptor->isa('Bio::EnsEMBL::DBSQL::SliceAdaptor'));
ok($slice_adaptor->db);

#
# fetch_by_region
#
my $slice = $slice_adaptor->fetch_by_region('chromosome',$CHR, $START, $END);
ok($slice->seq_region_name eq $CHR);
ok($slice->start == $START);
ok($slice->end   == $END);
ok($slice->seq_region_length == 62842997);
debug("slice seq_region length = " . $slice->seq_region_length());


#
# fetch_by_contig_name
#

my $projection = $slice->project('seqlevel');

#it is important to get a contig not cut off by slice start or end
unless(@$projection > 2) {
  warn("There aren't enough tiles in this path for this test to work");
}
my ($chr_start,$chr_end,$contig) = @{$projection->[1]};

ok($contig->length == ($chr_end - $chr_start + 1));

my $seq1 = $slice->subseq($chr_start, $chr_end);
my $seq2 = $contig->seq();

ok($seq1 eq $seq2);


#
# 12-13 fetch_by_fpc_name
#
#my $fpc_name = 'NT_011387';
#$slice = $slice_adaptor->fetch_by_supercontig_name($fpc_name);
#ok($new_slice->chr_start);
#ok($new_slice->chr_end);



#
# 14 - 15 fetch_by_clone_accession
#
#my $clone_acc = 'AL031658';
#$slice = $slice_adaptor->fetch_by_clone_accession($clone_acc);
#$new_slice = $slice_adaptor->fetch_by_clone_accession($clone_acc, $FLANKING);
#ok($new_slice->chr_start == $slice->chr_start - $FLANKING);
#ok($new_slice->chr_end   == $slice->chr_end   + $FLANKING);


#
# 16-17 fetch by transcript_stable_id
#
my $t_stable_id = 'ENST00000217315';
$slice = $slice_adaptor->fetch_by_transcript_stable_id($t_stable_id);
my $new_slice = $slice_adaptor->fetch_by_transcript_stable_id($t_stable_id,
                                                           $FLANKING);

ok($new_slice->start == $slice->start - $FLANKING);
ok($new_slice->end   == $slice->end   + $FLANKING);


#
# 18-19 fetch by transcript_id
#
my $transcript = $db->get_TranscriptAdaptor->fetch_by_stable_id($t_stable_id);
my $tid = $transcript->dbID;
$slice = $slice_adaptor->fetch_by_transcript_id($tid);
$new_slice = $slice_adaptor->fetch_by_transcript_id($tid, $FLANKING);
ok($new_slice->start == $slice->start - $FLANKING);
ok($new_slice->end   == $slice->end   + $FLANKING);
ok($slice->seq_region_length == 62842997);
debug("new slice seq_region length = " . $new_slice->seq_region_length());

#
# 20-23 fetch_by_gene_stable_id
#
my $g_stable_id = 'ENSG00000125964';
$slice = $slice_adaptor->fetch_by_gene_stable_id($g_stable_id);
$new_slice = $slice_adaptor->fetch_by_gene_stable_id($g_stable_id, $FLANKING);
ok($new_slice->start == $slice->start - $FLANKING);
ok($new_slice->end   == $slice->end   + $FLANKING);

#verify we can retrieve the gene from this slice
my $gene_found = 0;
foreach my $g (@{$slice->get_all_Genes}) {
  if($g->stable_id eq $g->stable_id) {
    $gene_found = 1;
    last;
  }
}
ok($gene_found);

# same test for flanking slice
$gene_found = 0;
foreach my $g (@{$new_slice->get_all_Genes}) {
  if($g->stable_id eq $g->stable_id) {
    $gene_found = 1;
    last;
  }
}
ok($gene_found);



#
#  fetch_by_region (entire region)
#
$slice = $slice_adaptor->fetch_by_region('chromosome',$CHR);
ok($slice->seq_region_name eq $CHR);
ok($slice->start == 1);


#
# fetch_by_misc_feature_attribute
#
my $flanking= 1000;
$slice = $slice_adaptor->fetch_by_misc_feature_attribute('superctg',
                                                         'NT_030871',
                                                         $flanking);

ok($slice->seq_region_name eq '20');
ok($slice->start == 59707812 - $flanking);
ok($slice->end   == 60855021 + $flanking);


#
# normalized projected slice
#

#
# a slice with a PAR region
# 24,25
#
$slice = $slice_adaptor->fetch_by_region( "chromosome", "Y", 9_000_000, 11_000_000, 1 );

my $results = $slice_adaptor->fetch_normalized_slice_projection( $slice );

debug( "Pseudo autosomal region results" );
for my $projection ( @$results ) {
  debug( "Start: ".$projection->[0] );
  debug( "End: ".$projection->[1] );
  debug( "Slice ".$projection->[2] );
  debug( "-----------" );
}

ok( @$results == 3 );
ok( $results->[1]->[2]->seq_region_name() eq "20" );

#
# a slice with a haplotype 
# 26,27
#

$slice =  $slice_adaptor->fetch_by_region( "chromosome", "20_HAP1", 30_000_000, 31_000_000, 1 );
$results = $slice_adaptor->fetch_normalized_slice_projection( $slice );

debug( "Haplotype projection results" ); 
for my $projection ( @$results ) {
  debug( "Start: ".$projection->[0] );
  debug( "End: ".$projection->[1] );
  debug( "Slice ".$projection->[2] );
  debug( "-----------" );
}

ok( @$results == 3 );
ok( $results->[0]->[2]->seq_region_name() eq "20" );
ok( $results->[1]->[2]->seq_region_name() eq "20_HAP1" );
ok( $results->[2]->[2]->seq_region_name() eq "20" );


#try a projection from chromosome 20 to supercontigs
$slice = $slice_adaptor->fetch_by_region('chromosome', "20", 29_252_000, 
                                         31_252_001 );

debug("Projection from chromosome 20 to supercontig");
my @projection = @{$slice->project('supercontig')};
ok(@projection == 1);
ok($projection[0]->[2]->seq_region_name eq 'NT_028392');
foreach my $seg (@projection) {
  my ($start, $end, $slice) = @$seg;
  debug("$start-$end " . $slice->seq_region_name);
}

#try a projection from clone to supercontig
$slice = $slice_adaptor->fetch_by_region('clone', 'AL121583.25');

debug("Projection from clone AL121583.25 to supercontig");

@projection = @{$slice->project('supercontig')};
ok(@projection == 1);
ok($projection[0]->[2]->seq_region_name eq 'NT_028392');
foreach my $seg (@projection) {
  my ($start, $end, $slice) = @$seg;
  debug("$start-$end -> " . $slice->start . '-'. $slice->end . ' ' . $slice->seq_region_name);
}

#
# test storing a couple of different slices
#
my $csa = $db->get_CoordSystemAdaptor();
my $cs  = $csa->fetch_by_name('contig');

$multi->save('core', 'seq_region', 'dna', 'dnac');

my $len = 50;
my $name = 'testregion';

#
# Store a slice with sequence
#

$slice = Bio::EnsEMBL::Slice->new(-COORD_SYSTEM    => $cs,
                                  -SEQ_REGION_NAME => $name,
                                  -SEQ_REGION_LENGTH => $len,
                                  -START           => 1,
                                  -END             => $len,
                                  -STRAND          => 1); 


my $seq   = 'A' x $len;



$slice_adaptor->store($slice, \$seq);

$slice = $slice_adaptor->fetch_by_region('contig', $name);

ok($slice->length == $len);
ok($slice->seq eq $seq);
ok($slice->seq_region_name eq $name);

#
# Store a slice without sequence
#

$cs  = $csa->fetch_by_name('chromosome');

$len = 50e6;
$name = 'testregion2';
$slice = Bio::EnsEMBL::Slice->new(-COORD_SYSTEM    => $cs,
                                  -SEQ_REGION_NAME => $name,
                                  -SEQ_REGION_LENGTH => $len,
                                  -START           => 1,
                                  -END             => $len,
                                  -STRAND          => 1); 

$slice_adaptor->store($slice);

$slice = $slice_adaptor->fetch_by_region('chromosome', $name);
ok($slice->length() == $len);
ok($slice->seq_region_length() == $len);
ok($slice->seq_region_name eq $name);

$multi->restore('core', 'seq_region', 'dna', 'dnac');


#
# There was a bug such that features were not being retrieved
# from slices that had a start < 1.  This is a test for that case.
#
$slice = $slice_adaptor->fetch_by_region('chromosome', '20', 1,35_000_000);
debug("slice start = " . $slice->start);
debug("slice end   = " . $slice->end);

my $sfs1 = $slice->get_all_SimpleFeatures();
print_features($sfs1);

$slice = $slice_adaptor->fetch_by_region('chromosome', '20', -10, 35_000_000);

debug("slice start = " . $slice->start);
debug("slice end   = " . $slice->end);

my $sfs2 = $slice->get_all_SimpleFeatures();
print_features($sfs2);

ok(@$sfs1 == @$sfs2);


#
# test fetch_by_name
#
$slice = $slice_adaptor->fetch_by_name($slice->name());

ok($slice->coord_system->name eq 'chromosome');
ok($slice->seq_region_name eq '20');
ok($slice->start == -10);
ok($slice->strand == 1);
ok($slice->end == 35e6);

$slice = $slice_adaptor->fetch_by_name('clone::AL121583.25:1:10000:-1');

ok($slice->coord_system->name eq 'clone');
ok($slice->seq_region_name eq 'AL121583.25');
ok($slice->start == 1);
ok($slice->end == 10000);
ok($slice->strand == -1);


#
# test fetch_all
#

#default no duplicates and reference only
my $slices = $slice_adaptor->fetch_all('chromosome',undef);
print_slices($slices);
ok(@$slices == 63);

# include duplicates
$slices = $slice_adaptor->fetch_all('chromosome', undef,0, 1);

print_slices($slices);
ok(@$slices == 62);


$slices = $slice_adaptor->fetch_all('contig', undef);

ok(@$slices == 12);

print_slices($slices);


$slices = $slice_adaptor->fetch_all('toplevel');

ok(@$slices == 1 && $slices->[0]->seq_region_name() eq '20');
print_slices($slices);

#
# test the fuzzy matching of clone accessions
#
my $clone_name = 'AL031658';
$slice = $slice_adaptor->fetch_by_region('clone', $clone_name);

debug("Fuzzy matched clone name $clone_name Got " . 
     $slice->seq_region_name);

ok($slice->seq_region_name =~ /$clone_name\.\d+/);

#make sure that it does not fuzzy match too much
$slice = $slice_adaptor->fetch_by_region('contig', $clone_name);
ok(!defined($slice));
print_slices([$slice]);


#
# Test the attribute getter/setter methods
#

$multi->hide('core', 'seq_region_attrib', 'attrib_type');

$slice = $slice_adaptor->fetch_by_region( "chromosome", "20" );
$slice_adaptor->set_seq_region_attrib( $slice, "GeneCount", 23322 );

my ($gene_count) = $slice->get_attribute('GeneCount');
ok($gene_count == 23322);

#
# try to store another attrib of the same name
#
$slice_adaptor->set_seq_region_attrib($slice, "GeneCount", 199);

## make sure the attrib type is only stored once
my $count =
  $db->db_handle->selectall_arrayref("SELECT count(*) FROM attrib_type")->[0]->[0];
ok($count == 1);

my @gene_counts = $slice->get_attribute('GeneCount');
ok(@gene_counts == 2); 

$multi->restore('core', 'seq_region_attrib', 'attrib_type');

sub print_slices {
  my $slices = shift;
  foreach my $slice (@$slices) {
    debug(($slice) ? $slice->name() : "UNDEF");
  } 
  debug( "Got ". scalar(@$slices));
}

sub print_features {
  my $fs = shift;
  foreach my $f (@$fs) {
    my $start  = $f->start();
    my $end    = $f->end();
    my $strand = $f->strand();
    debug("  $start-$end($strand)");
  }
}
