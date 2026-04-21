#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2024 Sam Lau (ByWater Solutions)
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use CGI        qw ( -utf8 );
use C4::Auth   qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use Koha::Libraries;
use Koha::Patrons;
use C4::Letters qw( GetPreparedLetter );
use C4::Scrubber;

my $query = CGI->new;

# if OPACVirtualCard is disabled, leave immediately
if ( !C4::Context->preference('OPACVirtualCard') ) {
    print $query->redirect("/cgi-bin/koha/errors/404.pl");
    exit;
}

my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name => "opac-virtual-card.tt",
        query         => $query,
        type          => "opac",
    }
);

my $lang = C4::Languages::getlanguage($query);

my $patron = Koha::Patrons->find($borrowernumber);

# Find and display patron image if allowed
my $image_html = '';
if ( C4::Context->preference('OPACpatronimages') && $patron->image ) {
    $template->param( display_patron_image => 1 );
    $image_html =
        '<div id="image-container"><img id="patron-image" src="/cgi-bin/koha/opac-patron-image.pl" alt="" /></div>';
}

# Get the desired barcode format
my $barcode_format = C4::Context->preference('OPACVirtualCardBarcode') || 'Code39';
my $barcode_html =
    qq{<div id="barcode-container"><svg id="patron-barcode" data-barcode="${\$patron->cardnumber}" data-barcode-format="$barcode_format"></svg></div>};

my $content = C4::Letters::GetPreparedLetter(
    (
        module      => 'members',
        letter_code => 'VIRTUALCARD',
        branchcode  => $patron->branchcode,
        tables      => {
            borrowers => $patron->borrowernumber,
            branches  => $patron->branchcode,
        },
        lang                   => $lang,
        message_transport_type => 'email',
        substitute             => {
            my_barcode => $barcode_html,
            my_image   => $image_html,
        },
    )
);

my $scrubber = C4::Scrubber->new('opac_virtual_card');
my $scrubbed = $scrubber->scrub( $content->{content} );

$content->{content} = $scrubbed;

$template->param(
    virtualcardview => 1,
    patron          => $patron,
    barcode_format  => $barcode_format,
    content         => $content,
);

output_html_with_http_headers $query, $cookie, $template->output, undef, { force_no_caching => 1 };
