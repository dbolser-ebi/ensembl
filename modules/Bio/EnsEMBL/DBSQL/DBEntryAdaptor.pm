# EnsEMBL External object reference reading writing adaptor for mySQL
#
# Copyright EMBL-EBI 2001
#
# Author: Arne Stabenau
# 
# Date : 06.03.2001
#

=head1 NAME

Bio::EnsEMBL::DBSQL::DBEntryAdaptor - 
MySQL Database queries to load and store external object references.

=head1 SYNOPSIS

$db_entry_adaptor = $db_adaptor->get_DBEntryAdaptor();
$dbEntry = $db_entry_adaptor->fetch_by_dbID($id);

=head1 CONTACT

  Arne Stabenau: stabenau@ebi.ac.uk
  Ewan Birney  : birney@ebi.ac.uk

=head1 APPENDIX

=cut

package Bio::EnsEMBL::DBSQL::DBEntryAdaptor;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBEntry;
use Bio::EnsEMBL::IdentityXref;

use vars qw(@ISA);
use strict;

@ISA = qw( Bio::EnsEMBL::DBSQL::BaseAdaptor );


=head2 fetch_by_dbID

  Arg [1]    : int $dbID
               the unique database identifier for the DBEntry to retrieve
  Example    : my $db_entry = $db_entry_adaptor->fetch_by_dbID($dbID);
  Description: retrieves a dbEntry from the database via its unique identifier 
  Returntype : Bio::EnsEMBL::DBEntry
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_dbID {
  my ($self, $dbID ) = @_;
  
  my $sth = $self->prepare( "
    SELECT xref.xref_id, xref.dbprimary_acc, xref.display_label,
           xref.version, xref.description,
           exDB.db_name, exDB.release,
		   es.synonym
      FROM xref, external_db exDB
     LEFT JOIN external_synonym es on es.xref_id = xref.xref_id
	 WHERE xref.xref_id = ?
		AND xref.xref_id = es.xref_id
		AND xref.external_db_id = exDB.external_db_id 
   " );

  $sth->execute($dbID);
  
  my $exDB;
  while ( my $arrayref = $sth->fetchrow_arrayref()){
	my %duplicate;
	my ( $refID, $dbprimaryId, $displayid, $version, $desc, $dbname, $release, $synonym) = @$arrayref;
    return undef if( ! defined $refID );
    
	unless ($duplicate{$refID}){
		$duplicate{$refID}++ ;
		
		$exDB = Bio::EnsEMBL::DBEntry->new
    		( -adaptor => $self,
      		-dbID => $dbID,
      		-primary_id => $dbprimaryId,
     		-display_id => $displayid,
      		-version => $version,
      		-release => $release,
      		-dbname => $dbname );
	
		$exDB->description( $desc ) if ( $desc );
	} # end duplicate
 
	$exDB->add_synonym( $synonym )  if ($synonym);
  
  } # end while

  return $exDB;
}


=head2 store

  Arg [1]    : ?? $exObj
  Arg [2]    : ?? $ensObject
  Arg [3]    : ?? $ensType
  Example    : 
  Description: 
  Returntype : 
  Exceptions : 
  Caller     : 

=cut


sub store {
    my ( $self, $exObj, $ensObject, $ensType ) = @_;
    my $dbJustInserted;

    # check if db exists
    # urlPattern dbname release
    my $sth = $self->prepare( "
     SELECT external_db_id
       FROM external_db
      WHERE db_name = ?
        AND release = ?
    " );
    $sth->execute( $exObj->dbname(), $exObj->release() );
    
    my $dbRef;
    
    if(  ($dbRef) =  $sth->fetchrow_array() ) {
        $dbJustInserted = 0;
    } else {
      # store it, get dbID for that
      $sth = $self->prepare( "
       INSERT ignore INTO external_db 
       SET db_name = ?,
           release = ?,
           status  = ?
     " );
	
      $sth->execute( $exObj->dbname(), $exObj->release(), $exObj->status);
      
      $dbJustInserted = 1;
      $sth = $self->prepare( "SELECT LAST_INSERT_ID()" );
      $sth->execute();
      ( $dbRef ) = $sth->fetchrow_array();
      if( ! defined $dbRef ) {
	$self->throw( "Database entry failed." );
      }
    }
    
    my $dbX;
    
    if(  $dbJustInserted ) {
      # dont have to check for existence; cannnot have been inserted at
      # this point, so $dbX is certainly undefined
      $dbX = undef;
    } else {
	$sth = $self->prepare( "
       SELECT xref_id
         FROM xref
        WHERE external_db_id = ?
          AND dbprimary_acc = ?
          AND version = ?
     " );
	$sth->execute( $dbRef, $exObj->primary_id(), 
		       $exObj->version() );
	( $dbX ) = $sth->fetchrow_array();
    }
    
    if( ! defined $dbX ) {
	
	$sth = $self->prepare( "
      INSERT ignore INTO xref 
       SET dbprimary_acc = ?,
           display_label = ?,
           version = ?,
           description = ?,
           external_db_id = ?
     " );
	$sth->execute( $exObj->primary_id(), $exObj->display_id(), $exObj->version(),
		       $exObj->description(), $dbRef);
	
	$sth = $self->prepare( "
      SELECT LAST_INSERT_ID()
    " );
	$sth->execute();
	( $dbX ) = $sth->fetchrow_array();
	
	# synonyms
	my $synonyms = $exObj->get_all_synonyms();
	foreach my $syn ( @{$synonyms} ) {
	    
#Check if this synonym is already in the database for the given primary id
	    my $sth = $self->prepare( "
     SELECT xref_id,
            synonym
       FROM external_synonym
      WHERE xref_id = ?
        AND synonym = ?
        " );
	    $sth->execute($dbX, $syn);
	    
	    my ($dbSyn) = $sth->fetchrow_array();
	    
	    #print STDERR $dbSyn[0],"\n";
	    
	    if( ! $dbSyn ) {
		$sth = $self->prepare( "
        INSERT ignore INTO external_synonym
         SET xref_id = ?,
            synonym = ?
        " );
		$sth->execute($dbX, $syn);
	    }
	}
		
	$sth = $self->prepare( "
   INSERT ignore INTO object_xref
     SET xref_id = ?,
         ensembl_object_type = ?,
         ensembl_id = ?
      " );
	
	$sth->execute( $dbX, $ensType, $ensObject );	
	$exObj->dbID( $dbX );
	$exObj->adaptor( $self );
	
	if ($exObj->isa('Bio::EnsEMBL::IdentityXref')) {
	    $sth = $self->prepare( "
      SELECT LAST_INSERT_ID()
      " );
	    $sth->execute();
	    my ( $Xidt ) = $sth->fetchrow_array();
	    
	    $sth = $self->prepare( "
             INSERT ignore INTO identity_xref
             SET object_xref_id = ?,
             query_identity = ?,
             target_identity = ? 
			 " );
	    $sth->execute( $Xidt, $exObj->query_identity, $exObj->target_identity );
	    
	}
    } else {
	$sth = $self->prepare ( "
              SELECT xref_id
              FROM object_xref
              WHERE xref_id = ?
              AND   ensembl_object_type = ?
              AND   ensembl_id = ?
			  ");
	
	$sth->execute($dbX, $ensType, $ensObject);
	my ($tst) = $sth->fetchrow_array;

	if (! defined $tst) {
	# line is already in xref table. Need to add to object_xref
	    $sth = $self->prepare( "
             INSERT ignore INTO object_xref
               SET xref_id = ?,
               ensembl_object_type = ?,
               ensembl_id = ?
			   ");
	
	    $sth->execute( $dbX, $ensType, $ensObject );	
	    $exObj->dbID( $dbX );
	    $exObj->adaptor( $self );

	    if ($exObj->isa('Bio::EnsEMBL::IdentityXref')) {
		$sth = $self->prepare( "
      SELECT LAST_INSERT_ID()
      " );
		
		$sth->execute();
		my ( $Xidt ) = $sth->fetchrow_array();
		
		$sth = $self->prepare( "
             INSERT ignore INTO identity_xref
             SET object_xref_id = ?,
             query_identity = ?,
             target_identity = ?
        " );
		$sth->execute( $Xidt, $exObj->query_identity, $exObj->target_identity );
		
	    }
	}
    }
        
    return $dbX;    
}


=head2 exists

  Arg [1]    : Bio::EnsEMBL::DBEntry $dbe
  Example    : if($dbID = $db_entry_adaptor->exists($dbe)) { do stuff; }
  Description: Returns the db id of this DBEntry if it exists in this database
               otherwise returns undef.  Exists is defined as an entry with 
               the same external_db and display_id
  Returntype : int
  Exceptions : thrown on incorrect args
  Caller     : GeneAdaptor::store, TranscriptAdaptor::store

=cut

sub exists {
  my ($self, $dbe) = @_ ;

  unless($dbe && ref $dbe && $dbe->isa('Bio::EnsEMBL::DBEntry')) {
    $self->throw("arg must be a Bio::EnsEMBL::DBEntry not [$dbe]");
  }
  
  my $sth = $self->prepare('SELECT x.xref_id 
                            FROM   xref x, external_db xdb
                            WHERE  x.external_db_id = xdb.external_db_id
                            AND    x.display_label = ? 
                            AND    xdb.db_name = ?');

  $sth->execute($dbe->display_id, $dbe->external_db);

  my ($dbID) = $sth->fetchrow_array;

  $sth->finish;

  return $dbID;
}


=head2 fetch_all_by_Gene

  Arg [1]    : Bio::EnsEMBL::Gene $gene 
               (The gene to retrieve DBEntries for)
  Example    : @db_entries = @{$db_entry_adaptor->fetch_by_Gene($gene)};
  Description: This should be changed, it modifies the gene passed in
  Returntype : listref of Bio::EnsEMBL::DBEntries
  Exceptions : none
  Caller     : Bio::EnsEMBL::Gene

=cut

sub fetch_all_by_Gene {
  my ( $self, $gene ) = @_;
 
  my $sth = $self->prepare("
  SELECT t.transcript_id, t.translation_id
                FROM transcript t
                WHERE t.gene_id = ?
  ");
  
  $sth->execute( $gene->dbID );

  while (my($transcript_id, $translation_id) = $sth->fetchrow) {
    if($translation_id) {
      foreach my $translink(@{ $self->_fetch_by_object_type( $translation_id, 'Translation' )} ) { 
        $gene->add_DBLink($translink);
      }
    }
    foreach my $translink(@{ $self->_fetch_by_object_type( $transcript_id, 'Transcript' )} ) { 
        $gene->add_DBLink($translink);
    }
  }
  if($gene->stable_id){
    my $genelinks = $self->_fetch_by_object_type( $gene->stable_id, 'Gene' );
    foreach my $genelink ( @$genelinks ) {
      $gene->add_DBLink( $genelink );
    }
  }
}


=head2 fetch_all_by_RawContig

  Arg [1]    : Bio::EnsEMBL::RawContig $contig
  Example    : @db_entries = @{$db_entry_adaptor->fetch_by_RawContig($contig)}
  Description: Retrieves a list of DBentries by a contig object
  Returntype : listref of Bio::EnsEMBL::DBEntries
  Exceptions : none
  Caller     : general

=cut

sub fetch_all_by_RawContig {
  my ( $self, $contig ) = @_;
  return $self->_fetch_by_object_type($contig->dbID, 'RawContig' );
}


=head2 fetch_all_by_Transcript

  Arg [1]    : Bio::EnsEMBL::Transcript
  Example    : @db_entries = @{$db_entry_adaptor->fetch_by_Gene($trans)};
  Description: This should be changed, it modifies the transcipt passed in
  Returntype : listref of Bio::EnsEMBL::DBEntries
  Exceptions : none
  Caller     : Bio::EnsEMBL::Gene 

=cut

sub fetch_all_by_Transcript {
  my ( $self, $trans ) = @_;

  my $sth = $self->prepare("
  SELECT t.translation_id 
                FROM transcript t
                WHERE t.transcript_id = ?
  ");
  
  $sth->execute( $trans->dbID );

  # 
  # Did this to be consistent with fetch_by_Gene, but don't like
  # it (filling in the object). I think returning the array would
  # be better. Oh well. EB
  #
  # ??
  
  while (my($translation_id) = $sth->fetchrow) {
	  foreach my $translink(@{ $self->_fetch_by_object_type( $translation_id, 'Translation' )} ) {
        $trans->add_DBLink($translink);
    }
  }
  foreach my $translink(@{ $self->_fetch_by_object_type( $trans->dbID, 'Transcript' )} ) {
     $trans->add_DBLink($translink);
  }
}


=head2 fetch_all_by_Translation

  Arg [1]    : Bio::EnsEMBL::Translation $trans
               (The translation to fetch database entries for)
  Example    : @db_entries = @{$db_entry_adptr->fetch_by_Translation($trans)};
  Description: Retrieves external database entries for an EnsEMBL translation
  Returntype : listref of Bio::EnsEMBL::DBEntries
  Exceptions : none
  Caller     : general

=cut

sub fetch_all_by_Translation {
  my ( $self, $trans ) = @_;
  return $self->_fetch_by_object_type( $trans->dbID(), 'Translation' );
}


=head2 fetch_by_object_type

  Arg [1]    : string $ensObj
  Arg [2]    : string $ensType
  			   (object type to be returned) 
  Example    : $self->_fetch_by_object_type( $translation_id, 'Translation' )
  Description: Fetches DBEntry by Object type
  Returntype : arrayref of DBEntry objects
  Exceptions : none
  Caller     : fetch_all_by_Gene
  			   fetch_all_by_Translation
			   fetch_all_by_Transcript
  			   fetch_all_by_RawContig

=cut

sub _fetch_by_object_type {
  my ( $self, $ensObj, $ensType ) = @_;
  my @out;
  
  if (!defined($ensObj)) {
    $self->throw("Can't fetch_by_EnsObject_type without an object");
  }
  if (!defined($ensType)) {
    $self->throw("Can't fetch_by_EnsObject_type without a type");
  }
  my $sth = $self->prepare("
    SELECT xref.xref_id, xref.dbprimary_acc, xref.display_label, xref.version,
           xref.description,
           exDB.db_name, exDB.release, exDB.status, 
           oxr.object_xref_id, 
           es.synonym, 
           idt.query_identity, idt.target_identity
    FROM   xref xref, external_db exDB, object_xref oxr 
    LEFT JOIN external_synonym es on es.xref_id = xref.xref_id 
    LEFT JOIN identity_xref idt on idt.object_xref_id = oxr.object_xref_id
    WHERE  xref.xref_id = oxr.xref_id
      AND  xref.external_db_id = exDB.external_db_id 
      AND  oxr.ensembl_id = ?
      AND  oxr.ensembl_object_type = ?
  ");
  
  $sth->execute($ensObj, $ensType);
  my %seen;
  
  while ( my $arrRef = $sth->fetchrow_arrayref() ) {
    my ( $refID, $dbprimaryId, $displayid, $version, 
	 $desc, $dbname, $release, $exDB_status, $objid, 
         $synonym, $queryid, $targetid ) = @$arrRef;
    my $exDB;
	my %obj_hash = ( 
		_adaptor => $self,
        _dbID => $refID,
        _primary_id => $dbprimaryId,
        _display_id => $displayid,
        _version => $version,
        _release => $release,
        _dbname => $dbname);
			    
    # using an outer join on the synonyms as well as on identity_xref, we
    # now have to filter out the duplicates (see v.1.18 for
    # original). Since there is at most one identity_xref row per xref,
    # this is easy enough; all the 'extra' bits are synonyms
    if ( !$seen{$refID} )  {
      $seen{$refID}++;
      
      if ((defined $queryid)) {         # an xref with similarity scores
        $exDB = Bio::EnsEMBL::IdentityXref->new_fast(\%obj_hash);       
		$exDB->query_identity($queryid);
        $exDB->target_identity($targetid);
        
      } else {
        $exDB = Bio::EnsEMBL::DBEntry->new_fast(\%obj_hash);
      }
      
      $exDB->description( $desc ) if ( $desc eq defined);
      
	  $exDB->status( $exDB_status ) if ( $exDB_status eq defined);
      
      push( @out, $exDB );
    } #if (!$seen{$refID})

#    $exDB still points to the same xref, so we can keep adding synonyms
     
    	$exDB->add_synonym( $synonym ) if ($synonym eq defined);    
  }                                     # while <a row from database>
  
  return \@out;
}

=head2 list_gene_ids_by_extids

  Arg [1]    : string $external_id
  Example    : none
  Description: Retrieve a list of geneid by an external identifier that is linked to 
               any of the genes transcripts, translations or the gene itself 
  Returntype : listref of strings
  Exceptions : none
  Caller     : unknown

=cut

sub list_gene_ids_by_extids{
   my ($self,$name) = @_;

   my %T = map { ($_,1) }
       $self->_type_by_external_id( $name, 'Translation', 'gene' ),
       $self->_type_by_external_id( $name, 'Transcript',  'gene' ),
       $self->_type_by_external_id( $name, 'Gene' );
   return keys %T;
}

=head2 geneids_by_extids

  Arg [1]    : string $external_id
  Example    : none
  Description: Retrieve a list of geneid by an external identifier that is linked to 
               any of the genes transcripts, translations or the gene itself 
			   (please not that this call is deprecated)
  Returntype : listref of strings
  Exceptions : none
  Caller     : unknown

=cut

sub geneids_by_extids{
   my ($self,$name) = @_;
   warn ("This method is deprecated please use 'list_gene_ids_by_extids");
   return $self->list_gene_ids_by_extids( $name );
}

=head2 list_transcript_ids_by_extids

  Arg [1]    : string $external_id
  Example    : none
  Description: Retrieve a list transcriptid by an external identifier that is linked to 
               any of the genes transcripts, translations or the gene itself 
  Returntype : listref of strings
  Exceptions : none
  Caller     : unknown

=cut

sub list_transcript_ids_by_extids{
   my ($self,$name) = @_;
   my @transcripts;

   my %T = map { ($_,1) }
       $self->_type_by_external_id( $name, 'Translation', 'transcript' ),
       $self->_type_by_external_id( $name, 'Transcript' );
   return keys %T;
}


=head2 transcriptids_by_extids

  Arg [1]    : string $external_id
  Example    : none
  Description: Retrieve a list transcriptid by an external identifier that is linked to 
               any of the genes transcripts, translations or the gene itself 
  Returntype : listref of strings
  Exceptions : none
  Caller     : unknown

=cut

sub transcriptids_by_extids{
   my ($self,$name) = @_;
   warn ("This method is deprecated please use 'list_transcript_ids_by_extids");
   return $self->list_transcript_ids_by_extids( $name );
}


=head2 translationids_by_extids

  Arg [1]    :  string $name 
  Example    :  none
  Description:  Gets a list of translation IDs by external display IDs 
  				(please note that this call is deprecated)
  Returntype :  list of Ints
  Exceptions :  none
  Caller     :  unknown

=cut

sub translationids_by_extids{
  my ($self,$name) = @_;
  warn ("This method is deprecated please use 'list_translation_ids_by_extids");
  return $self->list_translation_ids_by_extids( $name );
}


=head2 list_translation_ids_by_extids

  Arg [1]    :  string $name 
  Example    :  none
  Description:  Gets a list of translation IDs by external display IDs
  Returntype :  list of Ints
  Exceptions :  none
  Caller     :  unknown

=cut

sub list_translation_ids_by_extids{
  my ($self,$name) = @_;
  return $self->_type_by_external_id( $name, 'Translation' );
}

=head2 _type_by_external_id

  Arg [1]    : string $name
  			   (dbprimary_acc)
  Arg [2]    : string $ensType
  			   (Object_type)
  Arg [3]    : string $extraType
  			   (other object type to be returned) - optional
  Example    : $self->_type_by_external_id( $name, 'Translation' ) 
  Description: Gets
  Returntype : list of ensembl_IDs
  Exceptions : none
  Caller     : list_translation_ids_by_extids
               translationids_by_extids
  			   geneids_by_extids

=cut

sub _type_by_external_id{
  my ($self,$name,$ensType,$extraType) = @_;
   
  my $from_sql = '';
  my $where_sql = '';
  my $ID_sql = "oxr.ensembl_id";
  if(defined $extraType) {
    $ID_sql = "t.${extraType}_id";
    $from_sql = 'transcript as t, ';
    $where_sql = 't.'.lc($ensType).'_id = oxr.ensembl_id and ';
  }
  my @queries = (
    "select $ID_sql
       from $from_sql object_xref as oxr
      where $where_sql xref.dbprimary_acc = ? and
            xref.xref_id = oxr.xref_id and oxr.ensembl_object_type= ?",
    "select $ID_sql 
       from $from_sql xref, object_xref as oxr
      where $where_sql xref.display_label = ? and
            xref.xref_id = oxr.xref_id and oxr.ensembl_object_type= ?",
    "select $ID_sql
       from $from_sql object_xref as oxr, external_synonym as syn
      where $where_sql syn.synonym = ? and
            syn.xref_id = oxr.xref_id and oxr.ensembl_object_type= ?",
  );
# Increase speed of query by splitting the OR in query into three separate queries. This is because the 'or' statments render the index useless because MySQL can't use any
# fields in the index.
  
  my %hash = (); 
  foreach( @queries ) {
    my $sth = $self->prepare( $_ );
    $sth->execute("$name", $ensType);
    while( my $r = $sth->fetchrow_array() ) {
      $hash{$r} = 1;
    }
  }
  return keys %hash;
}


1;


__END__


Objectxref
=============
ensembl_id varchar, later int
ensembl_object_type  enum 
xref_id int
primary key (ensembl_id,ensembl_object_type,xref_id) 


xref
=================
xref_id int (autogenerated) 
external_db_id int
dbprimary_acc  varchar
version varchar

primary key (xref_id)

ExternalDescription
=======================
xref_id int
description varchar (256)

primary key (xref_id)

ExternalSynonym
=================
xref_id int
synonym varchar

primary key (external_id,synonym)


ExternalDB
===================
external_db_id int
db_name varchar
release varchar

