package CUFTS::Resolver::Controller::Root;

use strict;
use warnings;
use base 'Catalyst::Controller';

__PACKAGE__->config->{namespace} = '';

sub default : Private {
    my ( $self, $c ) = @_;
    $c->redirect('test');
    return;
}

sub base : Chained('/') PathPart('') CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{extra_js}  = [];
    $c->stash->{extra_css} = [];
}

sub site : Chained('base') PathPart('site') CaptureArgs(1) {
    my ($self, $c, $site_key) = @_;

    if ( $site_key =~ /^(.+)!sandbox$/ ) {
        $site_key = $1;
        $c->stash->{sandbox} = 1;
    }
    my $box = $c->stash->{sandbox} ? 'sandbox' : 'active';

    my $site = $c->model('CUFTS::Sites')->find({ key => $site_key });
    if ( !defined($site) ) {
        die("Unrecognized site key: $site_key");
    }
    $c->site( $site );

    # Set up site specific CSS file if it exists
    my $site_css = '/sites/' . $site->id . "/static/css/${box}/resolver.css";
    if ( -e ($c->config->{root} . $site_css) ) {
        $c->stash->{site_css_uri} = $c->uri_for( $site_css );
    }

    $c->stash->{extra_js}    = [];
    $c->stash->{extra_css}   = [];
    $c->stash->{breadcrumbs} = [];

    $c->stash->{additional_template_paths} = [ $c->config->{root} . '/sites/' . $site->id . "/${box}" ];

    push @{$c->stash->{breadcrumbs}}, [ $c->uri_for_site( $c->controller('Root')->action_for('site_index') ), $c->loc('Electronic Resources') ];
}

sub error : Chained('site') PathPart('error') Args(0) {
    my ( $self, $c ) = @_;
    $c->stash(
        template      => 'fatal_error.tt',
        fatal_errors  => $c->error,
    );
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    if ( scalar @{ $c->error } ) {
        $self->_end_error_handling($c);
    }

    return 1 if $c->response->status =~ /^3\d\d$/;
    return 1 if defined($c->response->body);

    unless ( $c->response->content_type ) {
        $c->response->content_type('text/html; charset=iso-8859-1');
    }

    eval { $c->detach('CUFTS::Resolver::View::TT'); };
    if ( scalar @{ $c->error } ) {
        $self->_end_error_handling($c);
    }

}

sub _end_error_handling {
    my ( $self, $c ) = @_;

    $c->stash(
        template      => 'fatal_error.tt',
        fatal_errors  => $c->error,
    );
    $c->forward('CUFTS::Resolver::View::TT');

    $c->{error} = [];
}


=back

=head1 NAME

CUFTS::Resolver::C::Root - Catalyst component

=head1 SYNOPSIS

See L<CUFTS::Resolver>

=head1 DESCRIPTION

Catalyst component.

=head1 AUTHOR

A clever guy

=head1 LICENSE

This library is free software . You can redistribute it and/or modify
it under the same terms as perl itself.

=cut

1;
