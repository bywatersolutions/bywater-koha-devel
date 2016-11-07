package CUFTS::Resolver::Controller::DocumentDelivery;
use Moose;
use namespace::autoclean;

use String::Util qw( trim hascontent );

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

CUFTS::Resolver::Controller::DocumentDelivery - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub base : Chained('/site') PathPart('docdel') CaptureArgs(1) {
    my ( $self, $c, $request_id ) = @_;

    my $request = $c->session->{requests}->{$request_id};
    if ( !defined $request ) {
        $c->stash->{errors} = [ $c->loc('Unable to find request in session.') ];
        return $c->forward( $c->controller('Root')->action_for('error') );
    }

    $c->stash->{request} = $request;
}

sub authenticate : Chained('base') PathPart('authenticate') Args(0) {
    my ( $self, $c ) = @_;

    # Need to load the site and figure out whatever custom
    # authentication needs to be done. Probably pass forward
    # some config things for the labels.

    # if ... form submitted ...

    my $name     = $c->request->params->{authenticate_name};
    my $password = $c->request->params->{authenticate_password};

    if ( hascontent($name) && hascontent($password) ) {

        # Do authentation
        return $c->forward( $c->controller->action_for('request') )
    }

    $c->stash->{template} = 'docdel_authenticate.tt';
}

sub request : Chained('base') PathPart('request') Args(0) {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'docdel_request.tt';
}

=encoding utf8

=head1 AUTHOR

Todd Holbrook

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
