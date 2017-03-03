package Koha::RDF::Trine::Store;

use Modern::Perl;

use C4::Context;

use RDF::Trine;
use RDF::Trine::Store::DBI;
use RDF::Trine::Parser;
use RDF::Trine::Statement;
use RDF::Trine::Node::Resource;

my $user = 'koha_kohadev';
my $pass = 'password';
my $modelname = 'koha_kohadev';

=head1 NAME

Koha::RDF::Trine::Store - base module for RDF::Trine

=head1 FUNCTIONS

=cut

sub new {

    my $class = shift;
    my $self={};
    bless $self, $class;
    $self->_init();
    return $self

}

sub _init {
    my $self = shift;
    # Copy the hash so that we're not modifying the original
    my $conf = C4::Context->config('trine');
    die "No 'trine' block is defined in koha-conf.xml.\n" if ( !$conf );
    my $trine =  { %{ $conf } };

    #FIXME We should support any type of model trine does

    # First, construct a DBI connection to your database

    my $dbh = DBI->connect( "DBI:mysql:database=".$trine->{database}, $trine->{user}, $trine->{pass} );
    my $store = RDF::Trine::Store::DBI->new( $modelname, $dbh );
    $self->{model} = RDF::Trine::Model->new($store);
    $self->{base} = C4::Context->preference('OPACBaseURL');
    return $self;

}

=head2 store_triple

Takes a hash with a subject->predicate->object triple and stores it in the store

=cut

sub store_triple {
    my ( $self, $params ) = @_;
    unless ( $params->{subject} && $params->{object} & $params->{predicate} ) {
        die "Must supply subject, object, and predicate for triple";
    }
    my $subject = RDF::Trine::Node::Resource->new( $params->{subject} );
    my $predicate = RDF::Trine::Node::Resource->new( $params->{predicate} );
    my $object = RDF::Trine::Node::Resource->new( $params->{object} );

    my $triple  = RDF::Trine::Statement->new($subject,$predicate,$object);
    $self->{model}->add_statement($triple);
#    my $parser     = RDF::Trine::Parser->new( 'ntriples' );
#    $parser->parse_into_model( $seld->{base}, $triple, $self->{model} );
    return;
}

=head2 get_triples

Takes a IRI URL whatever and returns the objects in the store

=cut

sub get_triples {
    my ( $self, $params ) = @_;
    die "Must supply a resource node" unless ( $params->{resource} );
    my $resource = RDF::Trine::Node::Resource->new( $params->{resource} );
    return $self->{model}->get_statements(undef,undef,$resource);
#    return $self->{model}->get_statements();
}

=head2 convert_and_store_record
=cut
