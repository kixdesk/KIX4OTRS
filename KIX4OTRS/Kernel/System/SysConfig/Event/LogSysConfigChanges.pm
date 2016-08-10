# --
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Rene(dot)Boehm(at)cape(dash)it(dot)de
# * Stefan(dot)Mehlig(at)cape(dash)it(dot)de
# * Dorothea(dot)Doerffel(at)cape(dash)it(dot)de
# --
# $Id$
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl-2.0.txt.
# --
package Kernel::System::SysConfig::Event::LogSysConfigChanges;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::SysConfigChangeLog',
    'Kernel::System::User',
);

=head1 NAME

Kernel::System::DependingDynamicField

=head1 SYNOPSIS

DependingDynamicField backend

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create a SysConfig::Event::LogSysConfigChanges object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $SysConfigEventLogSysConfigChangesObject = $Kernel::OM->Get('Kernel::System::SysConfig::Event::LogSysConfigChanges');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    $Self->{LogObject}                = $Kernel::OM->Get('Kernel::System::Log');
    $Self->{UserObject}               = $Kernel::OM->Get('Kernel::System::User');
    $Self->{SysConfigChangeLogObject} = $Kernel::OM->Get('Kernel::System::SysConfigChangeLog');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Event Data Config UserID)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }
    for (qw(Key ChangeType)) {
        if ( !$Param{Data}->{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_ in Data!" );
            return;
        }
    }

    # get user data
    my %UserData = $Self->{UserObject}->GetUserData(
        UserID => $Param{UserID},
    );

    if ( $Param{Data}->{ChangeType} == 1 ) {

        # write SysConfig changelog
        $Self->{SysConfigChangeLogObject}->Log(
            Priority => 'notice',
            Message  => "User $UserData{UserLogin} enabled option '$Param{Data}->{Key}'",
        );
    }
    elsif ( $Param{Data}->{ChangeType} == 2 ) {

        # write SysConfig changelog
        $Self->{SysConfigChangeLogObject}->Log(
            Priority => 'notice',
            Message  => "User $UserData{UserLogin} disabled option '$Param{Data}->{Key}'",
        );
    }
    elsif ( $Param{Data}->{ChangeType} == 3 ) {
        use Data::Dumper;
        my $OldValueDump = Dumper( $Param{Data}->{OldValue} );
        $OldValueDump =~ s/\$VAR1 = (.*?);/$1/g;
        my $NewValueDump = Dumper( $Param{Data}->{NewValue} );
        $NewValueDump =~ s/\$VAR1 = (.*?);/$1/g;

        # write SysConfig changelog
        $Self->{SysConfigChangeLogObject}->Log(
            Priority => 'notice',
            Message  => "User $UserData{UserLogin} changed option '$Param{Data}->{Key}'\nOLD: "
                . $OldValueDump . "NEW: "
                . $NewValueDump,
        );
    }
    return;
}

1;
