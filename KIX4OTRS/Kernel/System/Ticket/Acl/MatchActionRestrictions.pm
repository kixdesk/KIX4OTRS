# --
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Torsten(dot)Thau(at)cape(dash)it(dot)de
# * Martin(dot)Balzarek(at)cape(dash)it(dot)de
# * Dorothea(dot)Doerffel(at)cape(dash)it(dot)de
#
# --
# $Id$
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
package Kernel::System::Ticket::Acl::MatchActionRestrictions;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # create required objects
    $Self->{ConfigObject} = $Kernel::OM->Get('Kernel::Config');
    $Self->{LogObject}    = $Kernel::OM->Get('Kernel::System::Log');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get required params...
    for (qw(Config Acl)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }

    # get ticket data match properties and restricted ticket actions
    my $RestrictionDataRef
        = $Self->{ConfigObject}->Get('Match::ExcludedAction') || '';
    return if ( !$RestrictionDataRef || ref($RestrictionDataRef) ne 'HASH' );

    # build ACL for each restriction
    my $Counter = 1;
    for my $CurrRestriction ( keys %{$RestrictionDataRef} ) {
        next if !$CurrRestriction;
        next if !$RestrictionDataRef->{$CurrRestriction};

        # build ticket data restriction as hash with array references (e.g. Type => ['default'], Queue => ['Raw'])
        my %PropertiesTicket;
        my @MatchRestrictions = split( '\|\|\|', $CurrRestriction );
        for my $Criteria (@MatchRestrictions) {
            my @MatchRestriction = split( ':::', $Criteria );
            if ( $MatchRestriction[0] && $MatchRestriction[1] ) {
                my @MatchValues = split( ';', $MatchRestriction[1] );
                $PropertiesTicket{ $MatchRestriction[0] } = \@MatchValues;
            }
        }

        # build blacklist as hash with array references (e.g. Type => ['default'], Queue => ['Raw'])
        my @TicketActions = split( ';', $RestrictionDataRef->{$CurrRestriction} );
        if (scalar @TicketActions) {
            $Param{Acl}->{ '803_MatchActionRestrictions' . $Counter } = {
                Properties => {
                    Ticket => \%PropertiesTicket,
                },
                PossibleNot => {
                    Action => \@TicketActions,
                },
            };
        }
        $Counter++;
    }

    return 1;
}

1;
