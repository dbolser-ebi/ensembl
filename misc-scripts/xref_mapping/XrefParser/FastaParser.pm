package XrefParser::FastaParser;

use strict;
use Bio::SeqIO;
use File::Basename;

use base qw( XrefParser::BaseParser );

# Fasta file format, e.g.
# >foo peptide sequence for the foo gene
# MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAG
# PTRTVDTKQAHELAKSYGIPFIETSAKTRQGVEDAFYTLVREIRQYRMKKLNSSDDGTQG
# CMGLPCVVM

sub run {

  my ($self, $source_id, $species_id, $file) = @_;
  
  my $sio = Bio::SeqIO->new(-format=>'fasta' , -file=>$file );
  my $species_tax_id = $self->get_taxonomy_from_species_id($species_id);
  
  my @xrefs;
  while( my $seq = $sio->next_seq ) {

    # Test species if available
    if( my $sp = $seq->species ){
      if( my $tax_id = $sp->ncbi_taxid ){
        next if $tax_id != $species_tax_id;
      }
    }

    # build the xref object and store it
    my $xref;
    $xref->{ACCESSION}     = $seq->display_name;
    $xref->{LABEL}         = $seq->display_name;
    $xref->{DESCRIPTION}   = $seq->description;
    $xref->{SEQUENCE}      = $seq->seq;
    $xref->{SOURCE_ID}     = $source_id;
    $xref->{SPECIES_ID}    = $species_id;
    $xref->{SEQUENCE_TYPE} = $seq->alphabet eq 'protein' ? 'peptide' : 'dna';
    $xref->{STATUS}        = 'experimental';
    if( my $v = $seq->version ){ $xref->{VERSION} = $v };
    push @xrefs, $xref;

  }

  print scalar(@xrefs) . " Fasta xrefs succesfully parsed\n";

  $self->upload_xref_object_graphs(\@xrefs);

  print "Done\n";
  return 0; #successful
}

1;
