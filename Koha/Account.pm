package Koha::Account;

# Copyright 2016 ByWater Solutions
#
# This file is part of Koha.
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Carp;
use Data::Dumper;
use List::MoreUtils qw( uniq );

use C4::Circulation qw( ReturnLostItem );
use C4::Letters;
use C4::Log qw( logaction );
use C4::Stats qw( UpdateStats );

use Koha::Patrons;
use Koha::Account::Lines;
use Koha::Account::Offsets;
use Koha::DateUtils qw( dt_from_string );
use Koha::Exceptions;
use Koha::Exceptions::Account;

=head1 NAME

Koha::Accounts - Module for managing payments and fees for patrons

=cut

sub new {
    my ( $class, $params ) = @_;

    Carp::croak("No patron id passed in!") unless $params->{patron_id};

    return bless( $params, $class );
}

=head2 pay

This method allows payments to be made against fees/fines

Koha::Account->new( { patron_id => $borrowernumber } )->pay(
    {
        amount      => $amount,
        sip         => $sipmode,
        note        => $note,
        description => $description,
        library_id  => $branchcode,
        lines        => $lines, # Arrayref of Koha::Account::Line objects to pay
        account_type => $type,  # accounttype code
        offset_type => $offset_type,    # offset type code
    }
);

=cut

sub pay {
    my ( $self, $params ) = @_;

    my $amount       = $params->{amount};
    my $sip          = $params->{sip};
    my $description  = $params->{description};
    my $note         = $params->{note} || q{};
    my $library_id   = $params->{library_id};
    my $lines        = $params->{lines};
    my $type         = $params->{type} || 'payment';
    my $payment_type = $params->{payment_type} || undef;
    my $account_type = $params->{account_type};
    my $offset_type  = $params->{offset_type} || $type eq 'writeoff' ? 'Writeoff' : 'Payment';

    my $userenv = C4::Context->userenv;

    my $patron = Koha::Patrons->find( $self->{patron_id} );

    my $manager_id = $userenv ? $userenv->{number} : 0;
    my $interface = $params ? ( $params->{interface} || C4::Context->interface ) : C4::Context->interface;

    my @fines_paid; # List of account lines paid on with this payment

    my $balance_remaining = $amount; # Set it now so we can adjust the amount if necessary
    $balance_remaining ||= 0;

    my @account_offsets;

    # We were passed a specific line to pay
    foreach my $fine ( @$lines ) {
        my $amount_to_pay =
            $fine->amountoutstanding > $balance_remaining
          ? $balance_remaining
          : $fine->amountoutstanding;

        my $old_amountoutstanding = $fine->amountoutstanding;
        my $new_amountoutstanding = $old_amountoutstanding - $amount_to_pay;
        $fine->amountoutstanding($new_amountoutstanding)->store();
        $balance_remaining = $balance_remaining - $amount_to_pay;

        if ( $new_amountoutstanding == 0 && $fine->itemnumber && $fine->accounttype && ( $fine->accounttype eq 'L' ) )
        {
            C4::Circulation::ReturnLostItem( $self->{patron_id}, $fine->itemnumber );
        }

        my $account_offset = Koha::Account::Offset->new(
            {
                debit_id => $fine->id,
                type     => $offset_type,
                amount   => $amount_to_pay * -1,
            }
        );
        push( @account_offsets, $account_offset );

        if ( C4::Context->preference("FinesLog") ) {
            logaction(
                "FINES", 'MODIFY',
                $self->{patron_id},
                Dumper(
                    {
                        action                => 'fee_payment',
                        borrowernumber        => $fine->borrowernumber,
                        old_amountoutstanding => $old_amountoutstanding,
                        new_amountoutstanding => 0,
                        amount_paid           => $old_amountoutstanding,
                        accountlines_id       => $fine->id,
                        manager_id            => $manager_id,
                        note                  => $note,
                    }
                ),
                $interface
            );
            push( @fines_paid, $fine->id );
        }
    }

    # Were not passed a specific line to pay, or the payment was for more
    # than the what was owed on the given line. In that case pay down other
    # lines with remaining balance.
    my @outstanding_fines;
    @outstanding_fines = $self->lines->search(
        {
            amountoutstanding => { '>' => 0 },
        }
    ) if $balance_remaining > 0;

    foreach my $fine (@outstanding_fines) {
        my $amount_to_pay =
            $fine->amountoutstanding > $balance_remaining
          ? $balance_remaining
          : $fine->amountoutstanding;

        my $old_amountoutstanding = $fine->amountoutstanding;
        $fine->amountoutstanding( $old_amountoutstanding - $amount_to_pay );
        $fine->store();

        if ( $fine->amountoutstanding == 0 && $fine->itemnumber && $fine->accounttype && ( $fine->accounttype eq 'L' ) )
        {
            C4::Circulation::ReturnLostItem( $self->{patron_id}, $fine->itemnumber );
        }

        my $account_offset = Koha::Account::Offset->new(
            {
                debit_id => $fine->id,
                type     => $offset_type,
                amount   => $amount_to_pay * -1,
            }
        );
        push( @account_offsets, $account_offset );

        if ( C4::Context->preference("FinesLog") ) {
            logaction(
                "FINES", 'MODIFY',
                $self->{patron_id},
                Dumper(
                    {
                        action                => "fee_$type",
                        borrowernumber        => $fine->borrowernumber,
                        old_amountoutstanding => $old_amountoutstanding,
                        new_amountoutstanding => $fine->amountoutstanding,
                        amount_paid           => $amount_to_pay,
                        accountlines_id       => $fine->id,
                        manager_id            => $manager_id,
                        note                  => $note,
                    }
                ),
                $interface
            );
            push( @fines_paid, $fine->id );
        }

        $balance_remaining = $balance_remaining - $amount_to_pay;
        last unless $balance_remaining > 0;
    }

    $account_type ||=
        $type eq 'writeoff' ? 'W'
      : defined($sip)       ? "Pay$sip"
      :                       'Pay';

    $description ||= $type eq 'writeoff' ? 'Writeoff' : q{};

    my $payment = Koha::Account::Line->new(
        {
            borrowernumber    => $self->{patron_id},
            date              => dt_from_string(),
            amount            => 0 - $amount,
            description       => $description,
            accounttype       => $account_type,
            payment_type      => $payment_type,
            amountoutstanding => 0 - $balance_remaining,
            manager_id        => $manager_id,
            interface         => $interface,
            branchcode        => $library_id,
            note              => $note,
        }
    )->store();

    foreach my $o ( @account_offsets ) {
        $o->credit_id( $payment->id() );
        $o->store();
    }

    UpdateStats(
        {
            branch         => $library_id,
            type           => $type,
            amount         => $amount,
            borrowernumber => $self->{patron_id},
        }
    );

    if ( C4::Context->preference("FinesLog") ) {
        logaction(
            "FINES", 'CREATE',
            $self->{patron_id},
            Dumper(
                {
                    action            => "create_$type",
                    borrowernumber    => $self->{patron_id},
                    amount            => 0 - $amount,
                    amountoutstanding => 0 - $balance_remaining,
                    accounttype       => $account_type,
                    accountlines_paid => \@fines_paid,
                    manager_id        => $manager_id,
                }
            ),
            $interface
        );
    }

    if ( C4::Context->preference('UseEmailReceipts') ) {
        if (
            my $letter = C4::Letters::GetPreparedLetter(
                module                 => 'circulation',
                letter_code            => uc("ACCOUNT_$type"),
                message_transport_type => 'email',
                lang    => $patron->lang,
                tables => {
                    borrowers       => $self->{patron_id},
                    branches        => $self->{library_id},
                },
                substitute => {
                    credit => $payment,
                    offsets => \@account_offsets,
                },
              )
          )
        {
            C4::Letters::EnqueueLetter(
                {
                    letter                 => $letter,
                    borrowernumber         => $self->{patron_id},
                    message_transport_type => 'email',
                }
            ) or warn "can't enqueue letter $letter";
        }
    }

    return $payment->id;
}

=head3 add_credit

This method allows adding credits to a patron's account

my $credit_line = Koha::Account->new({ patron_id => $patron_id })->add_credit(
    {
        amount       => $amount,
        description  => $description,
        note         => $note,
        user_id      => $user_id,
        interface    => $interface,
        library_id   => $library_id,
        sip          => $sip,
        payment_type => $payment_type,
        type         => $credit_type,
        item_id      => $item_id
    }
);

$credit_type can be any of:
  - 'credit'
  - 'payment'
  - 'forgiven'
  - 'lost_item_return'
  - 'writeoff'

=cut

sub add_credit {

    my ( $self, $params ) = @_;

    # amount is passed as a positive value, but we store credit as negative values
    my $amount       = $params->{amount} * -1;
    my $description  = $params->{description} // q{};
    my $note         = $params->{note} // q{};
    my $user_id      = $params->{user_id};
    my $interface    = $params->{interface};
    my $library_id   = $params->{library_id};
    my $sip          = $params->{sip};
    my $payment_type = $params->{payment_type};
    my $type         = $params->{type} || 'payment';
    my $item_id      = $params->{item_id};

    unless ( $interface ) {
        Koha::Exceptions::MissingParameter->throw(
            error => 'The interface parameter is mandatory'
        );
    }

    my $schema = Koha::Database->new->schema;

    my $account_type = $Koha::Account::account_type_credit->{$type};
    $account_type .= $sip
        if defined $sip &&
           $type eq 'payment';

    my $line;

    $schema->txn_do(
        sub {

            # Insert the account line
            $line = Koha::Account::Line->new(
                {   borrowernumber    => $self->{patron_id},
                    date              => \'NOW()',
                    amount            => $amount,
                    description       => $description,
                    accounttype       => $account_type,
                    amountoutstanding => $amount,
                    payment_type      => $payment_type,
                    note              => $note,
                    manager_id        => $user_id,
                    interface         => $interface,
                    branchcode        => $library_id,
                    itemnumber        => $item_id,
                }
            )->store();

            # Record the account offset
            my $account_offset = Koha::Account::Offset->new(
                {   credit_id => $line->id,
                    type      => $Koha::Account::offset_type->{$type},
                    amount    => $amount
                }
            )->store();

            UpdateStats(
                {   branch         => $library_id,
                    type           => $type,
                    amount         => $amount,
                    borrowernumber => $self->{patron_id},
                }
            ) if grep { $type eq $_ } ('payment', 'writeoff') ;

            if ( C4::Context->preference("FinesLog") ) {
                logaction(
                    "FINES", 'CREATE',
                    $self->{patron_id},
                    Dumper(
                        {   action            => "create_$type",
                            borrowernumber    => $self->{patron_id},
                            amount            => $amount,
                            description       => $description,
                            amountoutstanding => $amount,
                            accounttype       => $account_type,
                            note              => $note,
                            itemnumber        => $item_id,
                            manager_id        => $user_id,
                            branchcode        => $library_id,
                        }
                    ),
                    $interface
                );
            }
        }
    );

    return $line;
}

=head3 add_debit

This method allows adding debits to a patron's account

my $debit_line = Koha::Account->new({ patron_id => $patron_id })->add_debit(
    {
        amount       => $amount,
        description  => $description,
        note         => $note,
        user_id      => $user_id,
        interface    => $interface,
        library_id   => $library_id,
        type         => $debit_type,
        item_id      => $item_id,
        issue_id     => $issue_id
    }
);

$debit_type can be any of:
  - overdue
  - lost_item
  - new_card
  - account
  - sundry
  - processing
  - rent
  - reserve
  - manual

=cut

sub add_debit {

    my ( $self, $params ) = @_;

    # amount should always be a positive value
    my $amount       = $params->{amount};

    unless ( $amount > 0 ) {
        Koha::Exceptions::Account::AmountNotPositive->throw(
            error => 'Debit amount passed is not positive'
        );
    }

    my $description  = $params->{description} // q{};
    my $note         = $params->{note} // q{};
    my $user_id      = $params->{user_id};
    my $interface    = $params->{interface};
    my $library_id   = $params->{library_id};
    my $type         = $params->{type};
    my $item_id      = $params->{item_id};
    my $issue_id     = $params->{issue_id};

    unless ( $interface ) {
        Koha::Exceptions::MissingParameter->throw(
            error => 'The interface parameter is mandatory'
        );
    }

    my $schema = Koha::Database->new->schema;

    unless ( exists($Koha::Account::account_type_debit->{$type}) ) {
        Koha::Exceptions::Account::UnrecognisedType->throw(
            error => 'Type of debit not recognised'
        );
    }

    my $account_type = $Koha::Account::account_type_debit->{$type};

    my $line;

    $schema->txn_do(
        sub {

            # Insert the account line
            $line = Koha::Account::Line->new(
                {   borrowernumber    => $self->{patron_id},
                    date              => \'NOW()',
                    amount            => $amount,
                    description       => $description,
                    accounttype       => $account_type,
                    amountoutstanding => $amount,
                    payment_type      => undef,
                    note              => $note,
                    manager_id        => $user_id,
                    interface         => $interface,
                    itemnumber        => $item_id,
                    issue_id          => $issue_id,
                    branchcode        => $library_id,
                    ( $type eq 'overdue' ? ( status => 'UNRETURNED' ) : ()),
                }
            )->store();

            # Record the account offset
            my $account_offset = Koha::Account::Offset->new(
                {   debit_id => $line->id,
                    type      => $Koha::Account::offset_type->{$type},
                    amount    => $amount
                }
            )->store();

            if ( C4::Context->preference("FinesLog") ) {
                logaction(
                    "FINES", 'CREATE',
                    $self->{patron_id},
                    Dumper(
                        {   action            => "create_$type",
                            borrowernumber    => $self->{patron_id},
                            amount            => $amount,
                            description       => $description,
                            amountoutstanding => $amount,
                            accounttype       => $account_type,
                            note              => $note,
                            itemnumber        => $item_id,
                            manager_id        => $user_id,
                        }
                    ),
                    $interface
                );
            }
        }
    );

    return $line;
}

=head3 balance

my $balance = $self->balance

Return the balance (sum of amountoutstanding columns)

=cut

sub balance {
    my ($self) = @_;
    return $self->lines->total_outstanding;
}

=head3 outstanding_debits

my $lines = Koha::Account->new({ patron_id => $patron_id })->outstanding_debits;

It returns the debit lines with outstanding amounts for the patron.

In scalar context, it returns a Koha::Account::Lines iterator. In list context, it will
return a list of Koha::Account::Line objects.

=cut

sub outstanding_debits {
    my ($self) = @_;

    return $self->lines->search(
        {
            amount            => { '>' => 0 },
            amountoutstanding => { '>' => 0 }
        }
    );
}

=head3 outstanding_credits

my $lines = Koha::Account->new({ patron_id => $patron_id })->outstanding_credits;

It returns the credit lines with outstanding amounts for the patron.

In scalar context, it returns a Koha::Account::Lines iterator. In list context, it will
return a list of Koha::Account::Line objects.

=cut

sub outstanding_credits {
    my ($self) = @_;

    return $self->lines->search(
        {
            amount            => { '<' => 0 },
            amountoutstanding => { '<' => 0 }
        }
    );
}

=head3 non_issues_charges

my $non_issues_charges = $self->non_issues_charges

Calculates amount immediately owing by the patron - non-issue charges.

Charges exempt from non-issue are:
* Res (holds) if HoldsInNoissuesCharge syspref is set to false
* Rent (rental) if RentalsInNoissuesCharge syspref is set to false
* Manual invoices if ManInvInNoissuesCharge syspref is set to false

=cut

sub non_issues_charges {
    my ($self) = @_;

    # FIXME REMOVE And add a warning in the about page + update DB if length(MANUAL_INV) > 5
    my $ACCOUNT_TYPE_LENGTH = 5;    # this is plain ridiculous...

    my @not_fines;
    push @not_fines, 'Res'
      unless C4::Context->preference('HoldsInNoissuesCharge');
    push @not_fines, 'Rent'
      unless C4::Context->preference('RentalsInNoissuesCharge');
    unless ( C4::Context->preference('ManInvInNoissuesCharge') ) {
        my $dbh = C4::Context->dbh;
        push @not_fines,
          @{
            $dbh->selectcol_arrayref(q|
                SELECT authorised_value FROM authorised_values WHERE category = 'MANUAL_INV'
            |)
          };
    }
    @not_fines = map { substr( $_, 0, $ACCOUNT_TYPE_LENGTH ) } uniq(@not_fines);

    return $self->lines->search(
        {
            accounttype    => { -not_in => \@not_fines }
        },
    )->total_outstanding;
}

=head3 lines

my $lines = $self->lines;

Return all credits and debits for the user, outstanding or otherwise

=cut

sub lines {
    my ($self) = @_;

    return Koha::Account::Lines->search(
        {
            borrowernumber => $self->{patron_id},
        }
    );
}

=head3 reconcile_balance

$account->reconcile_balance();

Find outstanding credits and use them to pay outstanding debits.
Currently, this implicitly uses the 'First In First Out' rule for
applying credits against debits.

=cut

sub reconcile_balance {
    my ($self) = @_;

    my $outstanding_debits  = $self->outstanding_debits;
    my $outstanding_credits = $self->outstanding_credits;

    while (     $outstanding_debits->total_outstanding > 0
            and my $credit = $outstanding_credits->next )
    {
        # there's both outstanding debits and credits
        $credit->apply( { debits => $outstanding_debits } );    # applying credit, no special offset

        $outstanding_debits = $self->outstanding_debits;

    }

    return $self;
}

1;

=head2 Name mappings

=head3 $offset_type

=cut

our $offset_type = {
    'credit'           => 'Manual Credit',
    'forgiven'         => 'Writeoff',
    'lost_item_return' => 'Lost Item',
    'payment'          => 'Payment',
    'writeoff'         => 'Writeoff',
    'account'          => 'Account Fee',
    'reserve'          => 'Reserve Fee',
    'processing'       => 'Processing Fee',
    'lost_item'        => 'Lost Item',
    'rent'             => 'Rental Fee',
    'overdue'          => 'OVERDUE',
    'manual_debit'     => 'Manual Debit',
    'hold_expired'     => 'Hold Expired'
};

=head3 $account_type_credit

=cut

our $account_type_credit = {
    'credit'           => 'C',
    'forgiven'         => 'FOR',
    'lost_item_return' => 'CR',
    'payment'          => 'Pay',
    'writeoff'         => 'W'
};

=head3 $account_type_debit

=cut

our $account_type_debit = {
    'account'       => 'A',
    'overdue'       => 'OVERDUE',
    'lost_item'     => 'L',
    'new_card'      => 'N',
    'sundry'        => 'M',
    'processing'    => 'PF',
    'rent'          => 'Rent',
    'reserve'       => 'Res',
    'manual_debit'  => 'M',
    'hold_expired'  => 'HE'
};

=head1 AUTHORS

=encoding utf8

Kyle M Hall <kyle.m.hall@gmail.com>
Tomás Cohen Arazi <tomascohen@gmail.com>
Martin Renvoize <martin.renvoize@ptfs-europe.com>

=cut
