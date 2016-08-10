# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# KIX4OTRS-Extensions Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Martin(dot)Balzarek(at)cape(dash)it(dot)de
# * Stefan(dot)Mehlig(at)cape(dash)it(dot)de
# * Rene(dot)Boehm(at)cape(dash)it(dot)de
# * Dorothea(dot)Doerffel(at)cape(dash)it(dot)de
# * Ralf(dot)Boehm(at)cape(dash)it(dot)de
# --
# $Id$
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTicketCompose;

use strict;
use warnings;

use Mail::Address;

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    # get form id
    $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check needed stuff
    if ( !$Self->{TicketID} ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('No TicketID is given!'),
            Comment => Translatable('Please contact the admin.'),
        );
    }

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # get config for frontend module
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");


    # KIX4OTRS-capeIT
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    my %Preferences = $UserObject->GetPreferences( UserID => $Self->{UserID} );
    $Self->{RedirectDestination} = $Preferences{RedirectAfterTicketClose} || '0';

    # EO KIX4OTRS-capeIT

    # check permissions
    my $Access = $TicketObject->TicketPermission(
        Type     => $Config->{Permission},
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID}
    );

    # error screen, don't show ticket
    if ( !$Access ) {
        return $LayoutObject->NoPermission(
            Message => $LayoutObject->{LanguageObject}->Translate( 'You need %s permissions!', $Config->{Permission} ),
            WithHeader => 'yes',
        );
    }

    # get ACL restrictions
    my %PossibleActions = ( 1 => $Self->{Action} );

    my $ACL = $TicketObject->TicketAcl(
        Data          => \%PossibleActions,
        Action        => $Self->{Action},
        TicketID      => $Self->{TicketID},
        ReturnType    => 'Action',
        ReturnSubType => '-',
        UserID        => $Self->{UserID},
    );
    my %AclAction = $TicketObject->TicketAclActionData();

    # check if ACL restrictions exist
    if ( $ACL || IsHashRefWithData( \%AclAction ) ) {

        my %AclActionLookup = reverse %AclAction;

        # show error screen if ACL prohibits this action
        if ( !$AclActionLookup{ $Self->{Action} } ) {
            return $LayoutObject->NoPermission( WithHeader => 'yes' );
        }
    }

    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 1
    );

    # get lock state
    my $TicketBackType = 'TicketBack';
    if ( $Config->{RequiredLock} ) {
        if ( !$TicketObject->TicketLockGet( TicketID => $Self->{TicketID} ) ) {
            $TicketObject->TicketLockSet(
                TicketID => $Self->{TicketID},
                Lock     => 'lock',
                UserID   => $Self->{UserID}
            );
            my $Owner = $TicketObject->TicketOwnerSet(
                TicketID  => $Self->{TicketID},
                UserID    => $Self->{UserID},
                NewUserID => $Self->{UserID},
            );

            # show lock state
            if ( !$Owner ) {
                return $LayoutObject->FatalError();
            }
            $TicketBackType .= 'Undo';
        }
        else {
            my $AccessOk = $TicketObject->OwnerCheck(
                TicketID => $Self->{TicketID},
                OwnerID  => $Self->{UserID},
            );
            if ( !$AccessOk ) {
                my $Output = $LayoutObject->Header(
                    Value     => $Ticket{Number},
                    Type      => 'Small',
                    BodyClass => 'Popup',
                );
                $Output .= $LayoutObject->Warning(
                    Message => Translatable('Sorry, you need to be the ticket owner to perform this action.'),
                    Comment => Translatable('Please change the owner first.'),
                );
                $Output .= $LayoutObject->Footer(
                    Type => 'Small',
                );
                return $Output;
            }
        }
    }

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get params
    my %GetParam;
    for (
        qw(
        From To Cc Bcc Subject Body InReplyTo References ResponseID ReplyArticleID StateID
        ArticleID ArticleTypeID TimeUnits Year Month Day Hour Minute FormID ReplyAll
        )
        )
    {
        $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
    }

    # KIX4OTRS-capeIT
    $GetParam{SubjectNoRe} = $ParamObject->GetParam( Param => 'SubjectNoRe' ) || '';

    # EO KIX4OTRS-capeIT

    # hash for check duplicated entries
    my %AddressesList;

    my @MultipleCustomer;
    my $CustomersNumber = $ParamObject->GetParam( Param => 'CustomerTicketCounterToCustomer' ) || 0;
    my $Selected = $ParamObject->GetParam( Param => 'CustomerSelected' ) || '';

    # get check item object
    my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

    if ($CustomersNumber) {

        my $CustomerCounter = 1;
        for my $Count ( 1 ... $CustomersNumber ) {
            my $CustomerElement = $ParamObject->GetParam( Param => 'CustomerTicketText_' . $Count );
            my $CustomerSelected = ( $Selected eq $Count ? 'checked="checked"' : '' );
            my $CustomerKey = $ParamObject->GetParam( Param => 'CustomerKey_' . $Count )
                || '';
            my $CustomerQueue = $ParamObject->GetParam( Param => 'CustomerQueue_' . $Count )
                || '';
            if ($CustomerElement) {

                if ( $GetParam{To} ) {
                    $GetParam{To} .= ', ' . $CustomerElement;
                }
                else {
                    $GetParam{To} = $CustomerElement;
                }

                # check email address
                my $CustomerErrorMsg = 'CustomerGenericServerErrorMsg';
                my $CustomerError    = '';
                for my $Email ( Mail::Address->parse($CustomerElement) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsg = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerError = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElement} && $CustomerError eq '' ) {
                    $CustomerErrorMsg = 'IsDuplicatedServerErrorMsg';
                    $CustomerError    = 'ServerError';
                }

                my $CustomerDisabled = '';
                my $CountAux         = $CustomerCounter++;
                if ( $CustomerError ne '' ) {
                    $CustomerDisabled = 'disabled="disabled"';
                    $CountAux         = $Count . 'Error';
                }

                if ( $CustomerQueue ne '' ) {
                    $CustomerQueue = $Count;
                }

                push @MultipleCustomer, {
                    Count            => $CountAux,
                    CustomerElement  => $CustomerElement,
                    CustomerSelected => $CustomerSelected,
                    CustomerKey      => $CustomerKey,
                    CustomerError    => $CustomerError,
                    CustomerErrorMsg => $CustomerErrorMsg,
                    CustomerDisabled => $CustomerDisabled,
                    CustomerQueue    => $CustomerQueue,
                };
                $AddressesList{$CustomerElement} = 1;
            }
        }
    }

    my @MultipleCustomerCc;
    my $CustomersNumberCc = $ParamObject->GetParam( Param => 'CustomerTicketCounterCcCustomer' ) || 0;

    if ($CustomersNumberCc) {
        my $CustomerCounterCc = 1;
        for my $Count ( 1 ... $CustomersNumberCc ) {
            my $CustomerElementCc = $ParamObject->GetParam( Param => 'CcCustomerTicketText_' . $Count );
            my $CustomerKeyCc     = $ParamObject->GetParam( Param => 'CcCustomerKey_' . $Count )
                || '';
            my $CustomerQueueCc = $ParamObject->GetParam( Param => 'CcCustomerQueue_' . $Count )
                || '';

            if ($CustomerElementCc) {

                if ( $GetParam{Cc} ) {
                    $GetParam{Cc} .= ', ' . $CustomerElementCc;
                }
                else {
                    $GetParam{Cc} = $CustomerElementCc;
                }

                # check email address
                my $CustomerErrorMsgCc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorCc    = '';
                for my $Email ( Mail::Address->parse($CustomerElementCc) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsgCc = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerErrorCc = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElementCc} && $CustomerErrorCc eq '' ) {
                    $CustomerErrorMsgCc = 'IsDuplicatedServerErrorMsg';
                    $CustomerErrorCc    = 'ServerError';
                }

                my $CustomerDisabledCc = '';
                my $CountAuxCc         = $CustomerCounterCc++;
                if ( $CustomerErrorCc ne '' ) {
                    $CustomerDisabledCc = 'disabled="disabled"';
                    $CountAuxCc         = $Count . 'Error';
                }

                if ( $CustomerQueueCc ne '' ) {
                    $CustomerQueueCc = $Count;
                }

                push @MultipleCustomerCc, {
                    Count            => $CountAuxCc,
                    CustomerElement  => $CustomerElementCc,
                    CustomerKey      => $CustomerKeyCc,
                    CustomerError    => $CustomerErrorCc,
                    CustomerErrorMsg => $CustomerErrorMsgCc,
                    CustomerDisabled => $CustomerDisabledCc,
                    CustomerQueue    => $CustomerQueueCc,
                };
                $AddressesList{$CustomerElementCc} = 1;
            }
        }
    }

    my @MultipleCustomerBcc;
    my $CustomersNumberBcc = $ParamObject->GetParam( Param => 'CustomerTicketCounterBccCustomer' ) || 0;

    if ($CustomersNumberBcc) {
        my $CustomerCounterBcc = 1;
        for my $Count ( 1 ... $CustomersNumberBcc ) {
            my $CustomerElementBcc = $ParamObject->GetParam( Param => 'BccCustomerTicketText_' . $Count );
            my $CustomerKeyBcc     = $ParamObject->GetParam( Param => 'BccCustomerKey_' . $Count )
                || '';
            my $CustomerQueueBcc = $ParamObject->GetParam( Param => 'BccCustomerQueue_' . $Count )
                || '';

            if ($CustomerElementBcc) {

                if ( $GetParam{Bcc} ) {
                    $GetParam{Bcc} .= ', ' . $CustomerElementBcc;
                }
                else {
                    $GetParam{Bcc} = $CustomerElementBcc;
                }

                # check email address
                my $CustomerErrorMsgBcc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorBcc    = '';
                for my $Email ( Mail::Address->parse($CustomerElementBcc) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsgBcc = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerErrorBcc = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElementBcc} && $CustomerErrorBcc eq '' ) {
                    $CustomerErrorMsgBcc = 'IsDuplicatedServerErrorMsg';
                    $CustomerErrorBcc    = 'ServerError';
                }

                my $CustomerDisabledBcc = '';
                my $CountAuxBcc         = $CustomerCounterBcc++;
                if ( $CustomerErrorBcc ne '' ) {
                    $CustomerDisabledBcc = 'disabled="disabled"';
                    $CountAuxBcc         = $Count . 'Error';
                }

                if ( $CustomerQueueBcc ne '' ) {
                    $CustomerQueueBcc = $Count;
                }

                push @MultipleCustomerBcc, {
                    Count            => $CountAuxBcc,
                    CustomerElement  => $CustomerElementBcc,
                    CustomerKey      => $CustomerKeyBcc,
                    CustomerError    => $CustomerErrorBcc,
                    CustomerErrorMsg => $CustomerErrorMsgBcc,
                    CustomerDisabled => $CustomerDisabledBcc,
                    CustomerQueue    => $CustomerQueueBcc,
                };
                $AddressesList{$CustomerElementBcc} = 1;
            }
        }
    }

    # get Dynamic fields form ParamObject
    my %DynamicFieldValues;

    # get backend object
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value form the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} } =
            $DynamicFieldBackendObject->EditFieldValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ParamObject        => $ParamObject,
            LayoutObject       => $LayoutObject,
            );
    }

    # convert dynamic field values into a structure for ACLs
    my %DynamicFieldACLParameters;
    DYNAMICFIELD:
    for my $DynamicFieldItem ( sort keys %DynamicFieldValues ) {
        next DYNAMICFIELD if !$DynamicFieldItem;
        next DYNAMICFIELD if !$DynamicFieldValues{$DynamicFieldItem};

        $DynamicFieldACLParameters{ 'DynamicField_' . $DynamicFieldItem } = $DynamicFieldValues{$DynamicFieldItem};
    }
    $GetParam{DynamicField} = \%DynamicFieldACLParameters;

    # transform pending time, time stamp based on user time zone
    if (
        defined $GetParam{Year}
        && defined $GetParam{Month}
        && defined $GetParam{Day}
        && defined $GetParam{Hour}
        && defined $GetParam{Minute}
        )
    {
        %GetParam = $LayoutObject->TransformDateSelection(
            %GetParam,
        );
    }

    # get needed objects
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $MainObject        = $Kernel::OM->Get('Kernel::System::Main');

    # send email
    if ( $Self->{Subaction} eq 'SendEmail' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # KIX4OTRS-capeIT
        # Do not update any ticket state information, if there is no state selected
        # get valid state id
        # if ( !$GetParam{StateID} ) {
        #     my %Ticket = $TicketObject->TicketGet(
        #         TicketID => $Self->{TicketID},
        #         UserID   => 1,
        #     );
        #     $GetParam{StateID} = $Ticket{StateID};
        # }

        # my %StateData = $Kernel::OM->Get('Kernel::System::State')->StateGet( ID => $GetParam{StateID} );

        my %StateData;
        if ( $GetParam{StateID} ) {
            %StateData = $Kernel::OM->Get('Kernel::System::State')->StateGet( ID => $GetParam{StateID} );
        }

        # EO KIX4OTRS-capeIT

        my %Error;

        # get check item object
        my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Line . 'ErrorType' } = $Line . $CheckItemObject->CheckErrorType() . 'ServerErrorMsg';
                    $Error{ $Line . 'Invalid' }   = 'ServerError';
                }
                my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
                    Address => $Email->address()
                );
                if ($IsLocal) {
                    $Error{ $Line . 'IsLocalAddress' } = 'ServerError';
                }
            }
        }

        if ( $Error{ToIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'ToIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{CcIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'CcIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{BccIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'BccIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        # If is an action about attachments
        my $IsUpload = 0;

        # attachment delete
        my @AttachmentIDs = map {
            my ($ID) = $_ =~ m{ \A AttachmentDelete (\d+) \z }xms;
            $ID ? $ID : ();
        } $ParamObject->GetParamNames();

        COUNT:
        for my $Count ( reverse sort @AttachmentIDs ) {
            my $Delete = $ParamObject->GetParam( Param => "AttachmentDelete$Count" );
            next COUNT if !$Delete;
            $Error{AttachmentDelete} = 1;
            $UploadCacheObject->FormIDRemoveFile(
                FormID => $Self->{FormID},
                FileID => $Count,
            );
            $IsUpload = 1;
        }

        # attachment upload
        if ( $ParamObject->GetParam( Param => 'AttachmentUpload' ) ) {
            $IsUpload                = 1;
            %Error                   = ();
            $Error{AttachmentUpload} = 1;
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param => 'FileUpload',
            );
            $UploadCacheObject->FormIDAddFile(
                FormID      => $Self->{FormID},
                Disposition => 'attachment',
                %UploadStuff,
            );
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get time object
        my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

        # check pending date
        if ( $StateData{TypeName} && $StateData{TypeName} =~ /^pending/i ) {
            if ( !$TimeObject->Date2SystemTime( %GetParam, Second => 0 ) ) {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
            if (
                $TimeObject->Date2SystemTime( %GetParam, Second => 0 )
                < $TimeObject->SystemTime()
                )
            {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
        }

        # check if at least one recipient has been chosen
        if ( $IsUpload == 0 ) {
            if ( !$GetParam{To} ) {
                $Error{'ToInvalid'} = 'ServerError';
            }
        }

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    if ( $IsUpload == 0 ) {
                        $Error{ $Line . 'Invalid' } = 'ServerError';
                    }
                }
            }
        }

        # check subject
        if ( !$IsUpload && !$GetParam{Subject} ) {
            $Error{SubjectInvalid} = ' ServerError';
        }

        # check body
        if ( !$IsUpload && !$GetParam{Body} ) {
            $Error{BodyInvalid} = ' ServerError';
        }

        # check time units
        if (
            $ConfigObject->Get('Ticket::Frontend::AccountTime')
            && $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
            && $GetParam{TimeUnits} eq ''
            )
        {
            if ( !$IsUpload ) {
                $Error{TimeUnitsInvalid} = 'ServerError';
            }
        }

        # prepare subject
        my $Tn = $TicketObject->TicketNumberLookup( TicketID => $Self->{TicketID} );
        $GetParam{Subject} = $TicketObject->TicketSubjectBuild(
            TicketNumber => $Tn,
            Subject      => $GetParam{Subject} || '',
        );

        # KIX4OTRS-capeIT
        if ( $GetParam{SubjectNoRe} ) {
            my $TicketSubjectRe = $ConfigObject->Get('Ticket::SubjectRe');
            $GetParam{Subject} =~ s/^($TicketSubjectRe(\[\d+\])?: )+//;
            $GetParam{IsChecked} = 'checked="checked"';
        }

        # EO KIX4OTRS-capeIT

        my %ArticleParam;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' )
        {

            # use ticket QueueID in compose modules
            $GetParam{QueueID} = $Ticket{QueueID};

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }
                my $Object = $Jobs{$Job}->{Module}->new( %{$Self}, Debug => $Self->{Debug} );

                # get params
                for ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # ticket params
                %ArticleParam = (
                    %ArticleParam,
                    $Object->ArticleOption( %GetParam, Config => $Jobs{$Job} ),
                );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # KIX4OTRS-capeIT
            # my $PossibleValuesFilter;
            # EO KIX4OTRS-capeIT

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        Action        => $Self->{Action},
                        TicketID      => $Self->{TicketID},
                        ReturnType    => 'Ticket',
                        ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data          => \%AclData,
                        UserID        => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        # KIX4OTRS-capeIT
                        # %{$PossibleValuesFilter} = map { $_ => $PossibleValues->{$_} }
                        %{ $DynamicFieldConfig->{ShownPossibleValues} }
                            = map { $_ => $PossibleValues->{$_} }

                            # EO KIX4OTRS-capeIT
                            keys %Filter;
                    }
                }
            }

            # KIX4OTRS-capeIT
        }

        # get shown or hidden fields
        $Self->_GetShownDynamicFields();

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # EO KIX4OTRS-capeIT

            my $ValidationResult;

            # KIX4OTRS-capeIT
            # do not validate on attachment upload or if field is disabled
            # if ( !$IsUpload ) {
            if (
                !$IsUpload
                && $DynamicFieldConfig->{Shown}
                )
            {

                # EO KIX4OTRS-capeIT

                $ValidationResult = $DynamicFieldBackendObject->EditFieldValueValidate(
                    DynamicFieldConfig => $DynamicFieldConfig,

                    # KIX4OTRS-capeIT
                    # PossibleValuesFilter => $PossibleValuesFilter,
                    PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},

                    # EO KIX4OTRS-capeIT
                    ParamObject => $ParamObject,
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                );

                if ( !IsHashRefWithData($ValidationResult) ) {
                    return $LayoutObject->ErrorScreen(
                        Message => $LayoutObject->{LanguageObject}->Translate(
                            'Could not perform validation on field %s!',
                            $DynamicFieldConfig->{Label},
                        ),
                        Comment => Translatable('Please contact the admin.'),
                    );
                }

                # propagate validation error to the Error variable to be detected by the frontend
                if ( $ValidationResult->{ServerError} ) {
                    $Error{ $DynamicFieldConfig->{Name} } = ' ServerError';
                }

                # KIX4OTRS-capeIT
            }

            # EO KIX4OTRS-capeIT

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig => $DynamicFieldConfig,

                # KIX4OTRS-capeIT
                # PossibleValuesFilter => $PossibleValuesFilter,
                PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},

                # EO KIX4OTRS-capeIT
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                ServerError  => $ValidationResult->{ServerError}  || '',
                ErrorMessage => $ValidationResult->{ErrorMessage} || '',
                LayoutObject => $LayoutObject,
                ParamObject  => $ParamObject,
                AJAXUpdate   => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # check if there is an error
        if (%Error) {

            my $Output = $LayoutObject->Header(
                Value     => $Ticket{TicketNumber},
                Type      => 'Small',
                BodyClass => 'Popup',
            );
            $GetParam{StandardResponse} = $GetParam{Body};
            $Output .= $Self->_Mask(
                TicketID   => $Self->{TicketID},
                NextStates => $Self->_GetNextStates(
                    %GetParam,
                ),
                ResponseFormat      => $LayoutObject->Ascii2Html( Text => $GetParam{Body} ),
                Errors              => \%Error,
                MultipleCustomer    => \@MultipleCustomer,
                MultipleCustomerCc  => \@MultipleCustomerCc,
                MultipleCustomerBcc => \@MultipleCustomerBcc,
                Attachments         => \@Attachments,
                GetParam            => \%GetParam,
                TicketBackType      => $TicketBackType,
                %Ticket,
                DynamicFieldHTML => \%DynamicFieldHTML,
                %GetParam,
            );
            $Output .= $LayoutObject->Footer(
                Type => 'Small',
            );
            return $Output;
        }

        # replace <OTRS_TICKET_STATE> with next ticket state name
        if ( $StateData{Name} ) {
            $GetParam{Body} =~ s/<OTRS_TICKET_STATE>/$StateData{Name}/g;
            $GetParam{Body} =~ s/&lt;OTRS_TICKET_STATE&gt;/$StateData{Name}/g;
        }

        # get pre loaded attachments
        my @AttachmentData = $UploadCacheObject->FormIDGetAllFilesData(
            FormID => $Self->{FormID},
        );

        # get submit attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );
        if (%UploadStuff) {
            push @AttachmentData, \%UploadStuff;
        }

        # get recipients
        my $Recipients = '';
        LINE:
        for my $Line (qw(To Cc Bcc)) {

            next LINE if !$GetParam{$Line};

            if ($Recipients) {
                $Recipients .= ', ';
            }

            # KIX4OTRS-capeIT
            # add To Cc or Bcc to history entry
            # $Recipients .= $GetParam{$Line};
            $Recipients .= $GetParam{$Line} . ' (' . $Line . ')';

            # KIX4OTRS-capeIT
        }

        my $MimeType = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $MimeType = 'text/html';

            # remove unused inline images
            my @NewAttachmentData;
            ATTACHMENT:
            for my $Attachment (@AttachmentData) {
                my $ContentID = $Attachment->{ContentID};
                if (
                    $ContentID
                    && ( $Attachment->{ContentType} =~ /image/i )
                    && ( $Attachment->{Disposition} eq 'inline' )
                    )
                {
                    my $ContentIDHTMLQuote = $LayoutObject->Ascii2Html(
                        Text => $ContentID,
                    );

                    # workaround for link encode of rich text editor, see bug#5053
                    my $ContentIDLinkEncode = $LayoutObject->LinkEncode($ContentID);
                    $GetParam{Body} =~ s/(ContentID=)$ContentIDLinkEncode/$1$ContentID/g;

                    # ignore attachment if not linked in body
                    next ATTACHMENT
                        if $GetParam{Body} !~ /(\Q$ContentIDHTMLQuote\E|\Q$ContentID\E)/i;
                }

                # remember inline images and normal attachments
                push @NewAttachmentData, \%{$Attachment};
            }
            @AttachmentData = @NewAttachmentData;

            # verify HTML document
            $GetParam{Body} = $LayoutObject->RichTextDocumentComplete(
                String => $GetParam{Body},
            );
        }

        # if there is no ArticleTypeID, use the default value
        my $ArticleTypeID = $GetParam{ArticleTypeID} // $TicketObject->ArticleTypeLookup(
            ArticleType => $Config->{DefaultArticleType},
        );

        # error page
        if ( !$ArticleTypeID ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Can not determine the ArticleType!'),
                Comment => Translatable('Please contact the admin.'),
            );
        }

        # send email
        my $ArticleID = $TicketObject->ArticleSend(
            ArticleTypeID  => $ArticleTypeID,
            SenderType     => 'agent',
            TicketID       => $Self->{TicketID},
            HistoryType    => 'SendAnswer',
            HistoryComment => "\%\%$Recipients",
            From           => $GetParam{From},
            To             => $GetParam{To},
            Cc             => $GetParam{Cc},
            Bcc            => $GetParam{Bcc},
            Subject        => $GetParam{Subject},
            UserID         => $Self->{UserID},
            Body           => $GetParam{Body},
            InReplyTo      => $GetParam{InReplyTo},
            References     => $GetParam{References},
            Charset        => $LayoutObject->{UserCharset},
            MimeType       => $MimeType,
            Attachment     => \@AttachmentData,
            %ArticleParam,
        );

        # error page
        if ( !$ArticleID ) {
            return $LayoutObject->ErrorScreen();
        }

        # time accounting
        if ( $GetParam{TimeUnits} ) {
            $TicketObject->TicketAccountTime(
                TicketID  => $Self->{TicketID},
                ArticleID => $ArticleID,
                TimeUnit  => $GetParam{TimeUnits},
                UserID    => $Self->{UserID},
            );
        }

        # set dynamic fields
        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # set the object ID (TicketID or ArticleID) depending on the field configration
            my $ObjectID = $DynamicFieldConfig->{ObjectType} eq 'Article' ? $ArticleID : $Self->{TicketID};

            # set the value
            my $Success = $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $ObjectID,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                UserID             => $Self->{UserID},
            );
        }

        # KIX4OTRS-capeIT
        # Do not update any ticket state information, if there is no state selected
        if ( $GetParam{StateID} ) {

            # EO KIX4OTRS-capeIT

            # set state
            $TicketObject->TicketStateSet(
                TicketID  => $Self->{TicketID},
                ArticleID => $ArticleID,
                StateID   => $GetParam{StateID},
                UserID    => $Self->{UserID},
            );

            # should I set an unlock?
            if ( $StateData{TypeName} =~ /^close/i ) {
                $TicketObject->TicketLockSet(
                    TicketID => $Self->{TicketID},
                    Lock     => 'unlock',
                    UserID   => $Self->{UserID},
                );
            }

            # set pending time
            elsif ( $StateData{TypeName} =~ /^pending/i ) {
                $TicketObject->TicketPendingTimeSet(
                    UserID   => $Self->{UserID},
                    TicketID => $Self->{TicketID},
                    Year     => $GetParam{Year},
                    Month    => $GetParam{Month},
                    Day      => $GetParam{Day},
                    Hour     => $GetParam{Hour},
                    Minute   => $GetParam{Minute},
                );
            }

            # KIX4OTRS-capeIT
        }

        # EO KIX4OTRS-capeIT

        # log use response id and reply article id (useful for response diagnostics)
        $TicketObject->HistoryAdd(
            Name         => "ResponseTemplate ($GetParam{ResponseID}/$GetParam{ReplyArticleID}/$ArticleID)",
            HistoryType  => 'Misc',
            TicketID     => $Self->{TicketID},
            CreateUserID => $Self->{UserID},
        );

        # remove pre submited attachments
        $UploadCacheObject->FormIDRemove( FormID => $GetParam{FormID} );

        # redirect
        # KIX4OTRS-capeIT
        # if ( $StateData{TypeName} =~ /^close/i ) {
        if (
            !$Self->{RedirectDestination}
            && $StateData{TypeName}
            && $StateData{TypeName} =~ /^close/i
            )
        {

            # EO KIX4OTRS-capeIT
            return $LayoutObject->PopupClose(
                URL => ( $Self->{LastScreenOverview} || 'Action=AgentDashboard' ),
            );
        }

        # load new URL in parent window and close popup
        return $LayoutObject->PopupClose(
            URL => "Action=AgentTicketZoom;TicketID=$Self->{TicketID};ArticleID=$ArticleID",
        );
    }

    # check for SMIME / PGP if customer has changed
    elsif ( $Self->{Subaction} eq 'AJAXUpdate' ) {

        my @ExtendedData;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' ) {

            # use ticket QueueID in compose modules
            $GetParam{QueueID} = $Ticket{QueueID};

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            JOB:
            for my $Job ( sort keys %Jobs ) {

                # load module
                next JOB if !$MainObject->Require( $Jobs{$Job}->{Module} );

                my $Object = $Jobs{$Job}->{Module}->new(
                    %{$Self},
                    Debug => $Self->{Debug},
                );

                # get params
                for my $Parameter ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter );
                }

                # run module
                my %Data = $Object->Data( %GetParam, Config => $Jobs{$Job} );

                # get AJAX param values
                if ( $Object->can('GetParamAJAX') ) {
                    %GetParam = ( %GetParam, $Object->GetParamAJAX(%GetParam) )
                }

                my $Key = $Object->Option( %GetParam, Config => $Jobs{$Job} );
                if ($Key) {
                    push(
                        @ExtendedData,
                        {
                            Name        => $Key,
                            Data        => \%Data,
                            SelectedID  => $GetParam{$Key},
                            Translation => 1,
                            Max         => 150,
                        }
                    );
                }
            }
        }

        my $NextStates = $Self->_GetNextStates(
            %GetParam,
        );

        # update Dynamc Fields Possible Values via AJAX
        my @DynamicFieldAJAX;

        # KIX4OTRS-capeIT
        my %DynamicFieldHTML;

        # EO KIX4OTRS-capeIT

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            # KIX4OTRS-capeIT
            # next DYNAMICFIELD if !$IsACLReducible;
            if ( !$IsACLReducible ) {
                $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                    $DynamicFieldBackendObject->EditFieldRender(
                    DynamicFieldConfig => $DynamicFieldConfig,
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                    LayoutObject    => $LayoutObject,
                    ParamObject     => $ParamObject,
                    AJAXUpdate      => 0,
                    UpdatableFields => $Self->_GetFieldsToUpdate(),
                    );

                next DYNAMICFIELD;
            }

            # EO KIX4OTRS-capeIT

            my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                DynamicFieldConfig => $DynamicFieldConfig,
            );

            # convert possible values key => value to key => key for ACLs using a Hash slice
            my %AclData = %{$PossibleValues};
            @AclData{ keys %AclData } = keys %AclData;

            # set possible values filter from ACLs
            my $ACL = $TicketObject->TicketAcl(
                %GetParam,
                Action        => $Self->{Action},
                TicketID      => $Self->{TicketID},
                QueueID       => $Self->{QueueID},
                ReturnType    => 'Ticket',
                ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                Data          => \%AclData,
                UserID        => $Self->{UserID},
            );
            if ($ACL) {
                my %Filter = $TicketObject->TicketAclData();

                # convert Filer key => key back to key => value using map
                %{$PossibleValues} = map { $_ => $PossibleValues->{$_} } keys %Filter;
            }

            my $DataValues = $DynamicFieldBackendObject->BuildSelectionDataGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                PossibleValues     => $PossibleValues,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
            ) || $PossibleValues;

            # add dynamic field to the list of fields to update
            push(
                @DynamicFieldAJAX,
                {
                    Name        => 'DynamicField_' . $DynamicFieldConfig->{Name},
                    Data        => $DataValues,
                    SelectedID  => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                    Translation => $DynamicFieldConfig->{Config}->{TranslatableValues} || 0,
                    Max         => 100,
                }
            );

            # KIX4OTRS-capeIT
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                LayoutObject    => $LayoutObject,
                ParamObject     => $ParamObject,
                AJAXUpdate      => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );

            # EO KIX4OTRS-capeIT
        }

        # KIX4OTRS-capeIT
        # get shown or hidden fields
        $Self->_GetShownDynamicFields();

        # use only dynamic fields which passed the acl
        my %TicketAclFormData = $TicketObject->TicketAclFormData();

        # use only dynamic fields which passed the acl
        my %Output;
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if $DynamicFieldConfig->{ObjectType} ne 'Ticket';

            if ( $DynamicFieldConfig->{Shown} == 1 ) {

                $Output{ ( "DynamicField_" . $DynamicFieldConfig->{Name} ) } = (
                    $DynamicFieldHTML{ $DynamicFieldConfig->{Name} }->{Label}
                        . qq~\n<div class="Field">~
                        . $DynamicFieldHTML{ $DynamicFieldConfig->{Name} }->{Field}
                        . qq~\n</div>\n<div class="Clear"></div>\n~
                );
            }
            else {
                $Output{ ( "DynamicField_" . $DynamicFieldConfig->{Name} ) } = "";
            }
        }

        my @FormDisplayOutput;
        if ( IsHashRefWithData( \%Output ) ) {
            push @FormDisplayOutput, {
                Name => 'FormDisplay',
                Data => \%Output,
                Max  => 10000,
            };
        }

        # EO KIX4OTRS-capeIT
        my $JSON = $LayoutObject->BuildSelectionJSON(
            [
                @ExtendedData,
                {
                    Name         => 'StateID',
                    Data         => $NextStates,
                    SelectedID   => $GetParam{StateID},
                    Translation  => 1,
                    PossibleNone => 1,
                    Max          => 100,
                },
                @DynamicFieldAJAX,

                # KIX4OTRS-capeIT
                @FormDisplayOutput,

                # EO KIX4OTRS-capeIT
            ],
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # KIX4OTRS-capeIT
    # update position
    elsif ( $Self->{Subaction} eq 'UpdatePosition' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my @Backends = $ParamObject->GetArray( Param => 'Backend' );

        # get new order
        my $Key  = $Self->{Action} . 'Position';
        my $Data = '';
        for my $Backend (@Backends) {
            $Data .= $Backend . ';';
        }

        # update ssession
        $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => $Key,
            Value     => $Data,
        );

        # update preferences
        if ( !$ConfigObject->Get('DemoSystem') ) {
            $UserObject->SetPreferences(
                UserID => $Self->{UserID},
                Key    => $Key,
                Value  => $Data,
            );
        }

        # redirect
        return $LayoutObject->Attachment(
            ContentType => 'text/html',
            Charset     => $LayoutObject->{UserCharset},
            Content     => '',
        );
    }

    # EO KIX4OTRS-capeIT
    else {
        my $Output = $LayoutObject->Header(
            Value     => $Ticket{TicketNumber},
            Type      => 'Small',
            BodyClass => 'Popup',
        );

        # KIX4OTRS-capeIT
        my $NoResponse = $ParamObject->GetParam( Param => 'NoResponse' ) || '';
        if ($NoResponse) {
            $GetParam{ResponseID} = 1;
        }

        # EO KIX4OTRS-capeIT

        # get std attachment object
        my $StdAttachmentObject = $Kernel::OM->Get('Kernel::System::StdAttachment');

        # add std. attachments to email
        if ( $GetParam{ResponseID} ) {
            my %AllStdAttachments = $StdAttachmentObject->StdAttachmentStandardTemplateMemberList(
                StandardTemplateID => $GetParam{ResponseID},
            );
            for ( sort keys %AllStdAttachments ) {
                my %Data = $StdAttachmentObject->StdAttachmentGet( ID => $_ );
                $UploadCacheObject->FormIDAddFile(
                    FormID      => $Self->{FormID},
                    Disposition => 'attachment',
                    %Data,
                );
            }
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get last customer article or selected article ...
        my %Data;
        if ( $GetParam{ArticleID} ) {
            %Data = $TicketObject->ArticleGet(
                ArticleID     => $GetParam{ArticleID},
                DynamicFields => 1,
            );
        }
        else {
            %Data = $TicketObject->ArticleLastCustomerArticle(
                TicketID      => $Self->{TicketID},
                DynamicFields => 1,
            );
        }

        # set OrigFrom for correct email quoting (xxxx wrote)
        $Data{OrigFrom} = $Data{From};

        # check article type and replace To with From (in case)
        my $SystemAddress  = $Kernel::OM->Get('Kernel::System::SystemAddress');
        if ( $Data{SenderType} !~ /customer/ ) {

            # replace From/To, To/From because sender is agent
            # KIX4OTRS
            # exchanging From and To, only makes sense if To is a system address
            # so we better check this first...
            # my $To = $Data{To};
            # $Data{To}   = $Data{From};
            # $Data{From} = $To;

            # $Data{ReplyTo} = '';
            for my $Email ( Mail::Address->parse( $Data{To} ) ) {
                my $IsLocal = $SystemAddress->SystemAddressIsLocalAddress(
                    Address => $Email->address(),
                );
                if ( !$IsLocal ) {
                    my $To = $Data{To};
                    $Data{From}    = $To;
                    $Data{To}      = $Data{From};
                    $Data{ReplyTo} = '';
                }
            }

            # EO KIX4OTRS
        }

        # build OrigFromName (to only use the realname)
        $Data{OrigFromName} = $Data{OrigFrom};
        $Data{OrigFromName} =~ s/<.*>|\(.*\)|\"|;|,//g;
        $Data{OrigFromName} =~ s/( $)|(  $)//g;

        # get customer data
        my %Customer;
        if ( $Ticket{CustomerUserID} ) {
            %Customer = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
                User => $Ticket{CustomerUserID}
            );
        }

        # get article to quote
        # KIX4OTRS-capeIT
        if ( defined $Data{ArticleID} && $Data{ArticleID} ) {

            # EO KIX4OTRS-capeIT
            $Data{Body} = $LayoutObject->ArticleQuote(
                TicketID          => $Self->{TicketID},
                ArticleID         => $Data{ArticleID},
                FormID            => $Self->{FormID},
                UploadCacheObject => $UploadCacheObject,
            );

            # KIX4OTRS-capeIT
        }

        # EO KIX4OTRS-capeIT

        # restrict number of body lines if configured
        if (
            $Data{Body}
            && $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines')
            )
        {
            my $MaxLines = $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines');

            # split body - one element per line
            my @Body = split "\n", $Data{Body};

            # only modify if body is longer than allowed
            if ( scalar @Body > $MaxLines ) {

                # splice to max. allowed lines and reassemble
                @Body = @Body[ 0 .. ( $MaxLines - 1 ) ];
                $Data{Body} = join "\n", @Body;
            }
        }

        if ( $LayoutObject->{BrowserRichText} ) {

            # prepare body, subject, ReplyTo ...
            # rewrap body if exists
            if ( $Data{Body} ) {
                $Data{Body} =~ s/\t/ /g;
                my $Quote = $LayoutObject->Ascii2Html(
                    Text => $ConfigObject->Get('Ticket::Frontend::Quote') || '',
                    HTMLResultMode => 1,
                );
                if ($Quote) {

                    # quote text
                    $Data{Body} = "<blockquote type=\"cite\">$Data{Body}</blockquote>\n";

                    # cleanup not compat. tags
                    $Data{Body} = $LayoutObject->RichTextDocumentCleanup(
                        String => $Data{Body},
                    );

                }
                else {
                    $Data{Body} = "<br/>" . $Data{Body};

                    if ( $Data{Created} ) {
                        $Data{Body} = $LayoutObject->{LanguageObject}->Translate('Date') .
                            ": $Data{Created}<br/>" . $Data{Body};
                    }

                    for (qw(Subject ReplyTo Reply-To Cc To From)) {
                        if ( $Data{$_} ) {
                            $Data{Body} = $LayoutObject->{LanguageObject}->Translate($_) .
                                ": $Data{$_}<br/>" . $Data{Body};
                        }
                    }

                    my $From = $LayoutObject->Ascii2RichText(
                        String => $Data{From},
                    );

                    my $MessageFrom = $LayoutObject->{LanguageObject}->Translate('Message from');
                    my $EndMessage  = $LayoutObject->{LanguageObject}->Translate('End message');

                    $Data{Body} = "<br/>---- $MessageFrom $From ---<br/><br/>" . $Data{Body};
                    $Data{Body} .= "<br/>---- $EndMessage ---<br/>";
                }
            }
        }
        else {

            # prepare body, subject, ReplyTo ...
            # rewrap body if exists
            if ( $Data{Body} ) {
                $Data{Body} =~ s/\t/ /g;
                my $Quote = $ConfigObject->Get('Ticket::Frontend::Quote');
                if ($Quote) {
                    $Data{Body} =~ s/\n/\n$Quote /g;
                    $Data{Body} = "\n$Quote " . $Data{Body};
                }
                else {
                    $Data{Body} = "\n" . $Data{Body};
                    if ( $Data{Created} ) {
                        $Data{Body} = $LayoutObject->{LanguageObject}->Translate('Date') .
                            ": $Data{Created}\n" . $Data{Body};
                    }

                    for (qw(Subject ReplyTo Reply-To Cc To From)) {
                        if ( $Data{$_} ) {
                            $Data{Body} = $LayoutObject->{LanguageObject}->Translate($_) .
                                ": $Data{$_}\n" . $Data{Body};
                        }
                    }

                    my $MessageFrom = $LayoutObject->{LanguageObject}->Translate('Message from');
                    my $EndMessage  = $LayoutObject->{LanguageObject}->Translate('End message');

                    $Data{Body} = "\n---- $MessageFrom $Data{From} ---\n\n" . $Data{Body};
                    $Data{Body} .= "\n---- $EndMessage ---\n";
                }
            }
        }

        # check if Cc recipients should be used
        if ( $ConfigObject->Get('Ticket::Frontend::ComposeExcludeCcRecipients') ) {
            $Data{Cc} = '';
        }

        # add not local To addresses to Cc
        for my $Email ( Mail::Address->parse( $Data{To} ) ) {
            my $IsLocal = $SystemAddress->SystemAddressIsLocalAddress(
                Address => $Email->address(),
            );
            if ( !$IsLocal ) {
                if ( $Data{Cc} ) {
                    $Data{Cc} .= ', ';
                }
                $Data{Cc} .= $Email->format();
            }
        }

        # check ReplyTo
        if ( $Data{ReplyTo} ) {
            $Data{To} = $Data{ReplyTo};
        }
        else {
            $Data{To} = $Data{From};

            # try to remove some wrong text to from line (by way of ...)
            # added by some strange mail programs on bounce
            $Data{To} =~ s/(.+?\<.+?\@.+?\>)\s+\(by\s+way\s+of\s+.+?\)/$1/ig;
        }

        # get to email (just "some@example.com")
        for my $Email ( Mail::Address->parse( $Data{To} ) ) {
            $Data{ToEmail} = $Email->address();
        }

        # KIX4OTRS-capeIT
        # Using the empty mail function there is no $Data{To}
        # therefore $Data{ToEmail} is not definied, but used later on
        if ($NoResponse) {
            $Data{ToEmail} = '';

            # disables automatic To replacing
            $Customer{UserEmail} = '';
        }

        # EO KIX4OTRS-capeIT

        # only reply to sender
        if ( !$GetParam{ReplyAll} ) {
            $Data{Cc}  = '';
            $Data{Bcc} = '';
        }

        # use customer database email
        # do not add customer email to cc, if article type is email-internal
        my $DataArticleType = $TicketObject->ArticleTypeLookup( ArticleTypeID => $Data{ArticleTypeID} );
        if (
            $ConfigObject->Get('Ticket::Frontend::ComposeAddCustomerAddress')
            && $DataArticleType !~ m{internal}
            )
        {

            # check if customer is in recipient list
            if ( $Customer{UserEmail} && $Data{ToEmail} !~ /^\Q$Customer{UserEmail}\E$/i ) {

                if ( $Data{SenderType} eq 'agent' && $DataArticleType !~ m{external} ) {
                    if ( $Data{To} ) {
                        $Data{To} .= ', ' . $Customer{UserEmail};
                    }
                    else {
                        $Data{To} = $Customer{UserEmail};
                    }
                }

                # replace To with customers database address
                elsif ( $ConfigObject->Get('Ticket::Frontend::ComposeReplaceSenderAddress') ) {

                    $Output .= $LayoutObject->Notify(
                        Data => $LayoutObject->{LanguageObject}->Translate(
                            'Address %s replaced with registered customer address.',
                            $Data{ToEmail},
                        ),

                        # KIX4OTRS-capeIT
                        Data => "To: ($Data{From}) replaced with database email!",

                        # EO KIX4OTRS-capeIT
                    );
                    $Data{To} = $Customer{UserEmail};
                }

                # add customers database address to Cc
                else {
                    $Output .= $LayoutObject->Notify(
                        Info => Translatable("Customer user automatically added in Cc."),
                    );
                    if ( $Data{Cc} ) {
                        $Data{Cc} .= ', ' . $Customer{UserEmail};
                    }
                    else {
                        $Data{Cc} = $Customer{UserEmail};
                    }
                }
            }
        }

        # find duplicate addresses
        my %Recipient;
        for my $Type (qw(To Cc Bcc)) {
            if ( $Data{$Type} ) {
                my $NewLine = '';
                for my $Email ( Mail::Address->parse( $Data{$Type} ) ) {
                    my $Address = lc $Email->address();

                    # only use email addresses with @ inside
                    if ( $Address && $Address =~ /@/ && !$Recipient{$Address} ) {
                        $Recipient{$Address} = 1;
                        my $IsLocal = $SystemAddress->SystemAddressIsLocalAddress(
                            Address => $Address,
                        );
                        if ( !$IsLocal ) {
                            if ($NewLine) {
                                $NewLine .= ', ';
                            }
                            $NewLine .= $Email->format();
                        }
                    }
                }
                $Data{$Type} = $NewLine;
            }
        }

        # get template
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');

        # use key StdResponse to pass the data to the template for legacy reasons,
        #   because existing systems may have it in their configuration as that was
        #   the key used before the internal switch to StandardResponse And StandardTemplate
        $Data{StdResponse} = $TemplateGenerator->Template(
            TicketID   => $Self->{TicketID},
            ArticleID  => $GetParam{ArticleID},
            TemplateID => $GetParam{ResponseID},
            Data       => \%Data,
            UserID     => $Self->{UserID},
        );

        # get salutation
        $Data{Salutation} = $TemplateGenerator->Salutation(
            TicketID => $Self->{TicketID},
            Data     => \%Data,
            UserID   => $Self->{UserID},
        );

        # get signature
        $Data{Signature} = $TemplateGenerator->Signature(
            TicketID => $Self->{TicketID},
            Data     => \%Data,
            UserID   => $Self->{UserID},
        );

        # $TemplateGenerator->Attributes() does not overwrite %Data, but it adds more keys
        %Data = $TemplateGenerator->Attributes(
            TicketID  => $Self->{TicketID},
            ArticleID => $GetParam{ArticleID},
            Data      => \%Data,
            UserID    => $Self->{UserID},
        );

        my $ResponseFormat = $ConfigObject->Get('Ticket::Frontend::ResponseFormat')
            || '[% Data.Salutation | html %]
[% Data.StdResponse | html %]
[% Data.Signature | html %]

[% Data.Created | Localize("TimeShort") %] - [% Data.OrigFromName | html %] [% Translate("wrote") | html %]:
[% Data.Body | html %]
';

        # KIX4OTRS-capeIT
        if ($NoResponse) {
            $Data{Subject} = $TicketObject->TicketSubjectBuild(
                TicketNumber => $Ticket{TicketNumber},
                Subject      => '  ',
            );
            my $TicketSubjectRe = $ConfigObject->Get('Ticket::SubjectRe');
            $Data{Subject} =~ s/^($TicketSubjectRe(\[\d+\])?: )+//;
            $Data{IsChecked} = 'checked="checked"';
            $Data{To}        = '';
            $Data{Cc}        = '';
            $Data{Bcc}       = '';
            @Attachments     = ();
            $ResponseFormat  = '
[% Data.Signature | html %]';
        }

        # EO KIX4OTRS-capeIT

        # make sure body is rich text
        my %DataHTML = %Data;
        if ( $LayoutObject->{BrowserRichText} ) {
            $ResponseFormat = $LayoutObject->Ascii2RichText(
                String => $ResponseFormat,
            );

            # restore qdata formatting for Output replacement
            $ResponseFormat =~ s/&quot;/"/gi;

            # html quote to have it correct in edit area
            $ResponseFormat = $LayoutObject->Ascii2Html(
                Text => $ResponseFormat,
            );

            # restore qdata formatting for Output replacement
            $ResponseFormat =~ s/&quot;/"/gi;

            # quote all non html content to have it correct in edit area
            KEY:
            for my $Key ( sort keys %DataHTML ) {
                next KEY if !$DataHTML{$Key};
                next KEY if $Key eq 'Salutation';
                next KEY if $Key eq 'Body';
                next KEY if $Key eq 'StdResponse';
                next KEY if $Key eq 'Signature';
                $DataHTML{$Key} = $LayoutObject->Ascii2RichText(
                    String => $DataHTML{$Key},
                );
            }
        }

        # build new repsonse format based on template
        $Data{ResponseFormat} = $LayoutObject->Output(
            Template => $ResponseFormat,
            Data     => { %Param, %DataHTML },
        );

        # check some values
        my %Error;
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$Data{$Line};
            for my $Email ( Mail::Address->parse( $Data{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Line . "Invalid" } = " ServerError"
                }
            }
        }
        if ( $Data{From} ) {
            for my $Email ( Mail::Address->parse( $Data{From} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{"FromInvalid"} .= $CheckItemObject->CheckError();
                }
            }
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # KIX4OTRS-capeIT
            # my $PossibleValuesFilter;
            # EO KIX4OTRS-capeIT

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        Action        => $Self->{Action},
                        TicketID      => $Self->{TicketID},
                        ReturnType    => 'Ticket',
                        ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data          => \%AclData,
                        UserID        => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        # KIX4OTRS-capeIT
                        # %{$PossibleValuesFilter} = map { $_ => $PossibleValues->{$_} }
                        %{ $DynamicFieldConfig->{ShownPossibleValues} }
                            = map { $_ => $PossibleValues->{$_} }

                            # EO KIX4OTRS-capeIT
                            keys %Filter;
                    }
                }
            }

            # to store dynamic field value from database (or undefined)
            my $Value;

            # only get values for Ticket fields (all screens based on AgentTickeActionCommon
            # generates a new article, then article fields will be always empty at the beginign)
            if ( $DynamicFieldConfig->{ObjectType} eq 'Ticket' ) {

                # get value stored on the database from Ticket
                $Value = $Ticket{ 'DynamicField_' . $DynamicFieldConfig->{Name} };
            }

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig => $DynamicFieldConfig,

                # KIX4OTRS-capeIT
                # PossibleValuesFilter => $PossibleValuesFilter,
                PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},

                # EO KIX4OTRS-capeIT
                Value => $Value,
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                LayoutObject    => $LayoutObject,
                ParamObject     => $ParamObject,
                AJAXUpdate      => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # KIX4OTRS-capeIT
        # get shown or hidden fields
        $Self->_GetShownDynamicFields();

        # EO KIX4OTRS-capeIT

        # build references if exist
        my $References = ( $Data{MessageID} || '' ) . ( $Data{References} || '' );

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' )
        {
            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }
                my $Object = $Jobs{$Job}->{Module}->new( %{$Self}, Debug => $Self->{Debug} );

                # get params
                for ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        # build view ...
        $Output .= $Self->_Mask(
            TicketID   => $Self->{TicketID},
            NextStates => $Self->_GetNextStates(
                %GetParam,
            ),
            Attachments         => \@Attachments,
            Errors              => \%Error,
            MultipleCustomer    => \@MultipleCustomer,
            MultipleCustomerCc  => \@MultipleCustomerCc,
            MultipleCustomerBcc => \@MultipleCustomerBcc,
            GetParam            => \%GetParam,
            ResponseID          => $GetParam{ResponseID},
            ReplyArticleID      => $GetParam{ArticleID},
            %Ticket,
            %Data,
            InReplyTo        => $Data{MessageID},
            References       => "$References",
            TicketBackType   => $TicketBackType,
            DynamicFieldHTML => \%DynamicFieldHTML,
            ArticleTypeID    => $GetParam{ArticleTypeID},    # don't use the ArticleID from the previous article
        );
        $Output .= $LayoutObject->Footer(
            Type => 'Small',
        );
        return $Output;
    }
}

sub _GetNextStates {
    my ( $Self, %Param ) = @_;

    # get next states
    my %NextStates = $Kernel::OM->Get('Kernel::System::Ticket')->TicketStateList(
        %Param,
        Action   => $Self->{Action},
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID},
    );
    return \%NextStates;
}

sub _Mask {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldNames = $Self->_GetFieldsToUpdate(
        OnlyDynamicFields => 1
    );

    # create a string with the quoted dynamic field names separated by commas
    # KIX4OTRS-capeIT
    if ( !$Param{DynamicFieldNamesStrg} ) {
        $Param{DynamicFieldNamesStrg} = '';
    }

    # EO KIX4OTRS-capeIT
    if ( IsArrayRefWithData($DynamicFieldNames) ) {
        FIELD:
        for my $Field ( @{$DynamicFieldNames} ) {
            $Param{DynamicFieldNamesStrg} .= ", '" . $Field . "'";
        }
    }

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get config for frontend module
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    my %State;
    if ( $Param{GetParam}->{StateID} ) {
        $State{SelectedID} = $Param{GetParam}->{StateID};
    }
    else {
        $State{SelectedValue} = $Config->{StateDefault};
    }
    $Param{NextStatesStrg} = $LayoutObject->BuildSelection(
        Data         => $Param{NextStates},
        Name         => 'StateID',
        PossibleNone => 1,
        %State,
        %Param,
        Class => 'Modernize',
    );

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    #  get article type
    my %ArticleTypeList;

    if ( $Config->{ArticleTypes} ) {

        my @ArticleTypesPossible = @{ $Config->{ArticleTypes} };
        for my $ArticleTypeID (@ArticleTypesPossible) {
            my $ArticleType = $TicketObject->ArticleTypeLookup(
                ArticleType => $ArticleTypeID,
            );
            $ArticleTypeList{$ArticleType} = $ArticleTypeID;
        }

        my %Selected;
        if ( $Param{ArticleTypeID} ) {
            $Selected{SelectedID} = $Param{ArticleTypeID};
        }
        else {
            $Selected{SelectedValue} = $Config->{DefaultArticleType};
        }

        $Param{ArticleTypesStrg} = $LayoutObject->BuildSelection(
            Data => \%ArticleTypeList,
            Name => 'ArticleTypeID',
            %Selected,
            Class => 'Modernize',
        );

        $LayoutObject->Block(
            Name => 'ArticleType',
            Data => \%Param,
        );
    }

    # build customer search auto-complete field
    $LayoutObject->Block(
        Name => 'CustomerSearchAutoComplete',
    );

    # prepare errors!
    if ( $Param{Errors} ) {
        for my $Error ( sort keys %{ $Param{Errors} } ) {
            $Param{$Error} = $LayoutObject->Ascii2Html(
                Text => $Param{Errors}->{$Error},
            );
        }
    }

    # get used calendar
    my $Calendar = $TicketObject->TicketCalendarGet(
        QueueID => $Param{QueueID},
        SLAID   => $Param{SLAID},
    );

    # pending data string
    $Param{PendingDateString} = $LayoutObject->BuildDateSelection(
        %Param,
        Format               => 'DateInputFormatLong',
        YearPeriodPast       => 0,
        YearPeriodFuture     => 5,
        DiffTime             => $ConfigObject->Get('Ticket::Frontend::PendingDiffTime') || 0,
        Class                => $Param{Errors}->{DateInvalid} || ' ',
        Validate             => 1,
        ValidateDateInFuture => 1,
        Calendar             => $Calendar,
    );

    # KIX4OTRS-capeIT
    # load KIXSidebar
    $Param{KIXSidebarContent} = $LayoutObject->AgentKIXSidebar(%Param);

    # EO KIX4OTRS-capeIT

    # Multiple-Autocomplete
    $Param{To} = ( scalar @{ $Param{MultipleCustomer} } ? '' : $Param{To} );
    if ( defined $Param{To} && $Param{To} ne '' ) {
        $Param{ToInvalid} = ''
    }

    $Param{Cc} = ( scalar @{ $Param{MultipleCustomerCc} } ? '' : $Param{Cc} );
    if ( defined $Param{Cc} && $Param{Cc} ne '' ) {
        $Param{CcInvalid} = ''
    }

    # Cc
    my $CustomerCounterCc = 0;
    if ( $Param{MultipleCustomerCc} ) {
        for my $Item ( @{ $Param{MultipleCustomerCc} } ) {
            $LayoutObject->Block(
                Name => 'CcMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Cc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CcCustomerErrorExplantion',
                );
            }
            $CustomerCounterCc++;
        }
    }

    if ( !$CustomerCounterCc ) {
        $Param{CcCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'CcMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterCc,
        },
    );

    # Bcc
    my $CustomerCounterBcc = 0;
    if ( $Param{MultipleCustomerBcc} ) {
        for my $Item ( @{ $Param{MultipleCustomerBcc} } ) {
            $LayoutObject->Block(
                Name => 'BccMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Bcc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'BccCustomerErrorExplantion',
                );
            }
            $CustomerCounterBcc++;
        }
    }

    if ( !$CustomerCounterBcc ) {
        $Param{BccCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'BccMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterBcc++,
        },
    );

    # To
    my $CustomerCounter = 0;
    if ( $Param{MultipleCustomer} ) {
        for my $Item ( @{ $Param{MultipleCustomer} } ) {
            $LayoutObject->Block(
                Name => 'MultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CustomerErrorExplantion',
                );
            }
            $CustomerCounter++;
        }
    }

    if ( !$CustomerCounter ) {
        $Param{CustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'MultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounter,
        },
    );

    if ( $Param{ToInvalid} && $Param{Errors} ) {
        $LayoutObject->Block(
            Name => 'ToServerErrorMsg',
        );
    }

    # set preselected values for Cc field
    if ( $Param{Cc} && $Param{Cc} ne '' && !$CustomerCounterCc ) {
        $LayoutObject->Block(
            Name => 'PreFilledCc',
        );

        # split To values
        for my $Email ( Mail::Address->parse( $Param{Cc} ) ) {
            $LayoutObject->Block(
                Name => 'PreFilledCcRow',
                Data => {
                    Email => $Email->address(),
                },
            );
        }
        $Param{Cc} = '';
    }

    # set preselected values for To field
    if ( $Param{To} ne '' && !$CustomerCounter ) {
        $LayoutObject->Block(
            Name => 'PreFilledTo',
        );

        # split To values
        for my $Email ( Mail::Address->parse( $Param{To} ) ) {
            $LayoutObject->Block(
                Name => 'PreFilledToRow',
                Data => {
                    Email => $Email->address(),
                },
            );
        }
        $Param{To} = '';
    }

    $LayoutObject->Block(
        Name => $Param{TicketBackType},
        Data => {

            #            FormID => $Self->{FormID},
            %Param,
        },
    );

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # Dynamic fields
    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # skip fields that HTML could not be retrieved
        next DYNAMICFIELD if !IsHashRefWithData(
            $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} }
        );

        # get the html strings form $Param
        my $DynamicFieldHTML = $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} };

        # KIX4OTRS-capeIT
        my $Class = "";
        if ( !$DynamicFieldConfig->{Shown} ) {
            $Class = " Hidden";
            $DynamicFieldHTML->{Field} =~ s/Validate_Required//ig;
        }

        # EO KIX4OTRS-capeIT
        $LayoutObject->Block(
            Name => 'DynamicField',
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},

                # KIX4OTRS-capeIT
                Class => $Class,

                # EO KIX4OTRS-capeIT
            },
        );

        # example of dynamic fields order customization
        $LayoutObject->Block(
            Name => 'DynamicField_' . $DynamicFieldConfig->{Name},
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }

    # show time accounting box
    if ( $ConfigObject->Get('Ticket::Frontend::AccountTime') ) {
        if ( $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime') ) {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabelMandatory',
                Data => \%Param,
            );
            $Param{TimeUnitsRequired} = 'Validate_Required';
        }
        else {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabel',
                Data => \%Param,
            );
            $Param{TimeUnitsRequired} = '';
        }
        $LayoutObject->Block(
            Name => 'TimeUnits',
            Data => \%Param,
        );
    }

    my $ShownOptionsBlock;

    # show spell check
    if ( $LayoutObject->{BrowserSpellChecker} ) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {},
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'SpellCheck',
            Data => {},
        );
    }

    # show address book
    if ( $LayoutObject->{BrowserJavaScriptSupport} ) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {},
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'AddressBook',
            Data => {},
        );
    }

    # add rich text editor
    if ( $LayoutObject->{BrowserRichText} ) {

        # use height/width defined for this screen
        $Param{RichTextHeight} = $Config->{RichTextHeight} || 0;
        $Param{RichTextWidth}  = $Config->{RichTextWidth}  || 0;

        $LayoutObject->Block(
            Name => 'RichText',
            Data => \%Param,
        );
    }

    # show attachments
    ATTACHMENT:
    for my $Attachment ( @{ $Param{Attachments} } ) {
        if (
            $Attachment->{ContentID}
            && $LayoutObject->{BrowserRichText}
            && ( $Attachment->{ContentType} =~ /image/i )
            && ( $Attachment->{Disposition} eq 'inline' )
            )
        {
            next ATTACHMENT;
        }
        $LayoutObject->Block(
            Name => 'Attachment',
            Data => $Attachment,
        );
    }

    # create & return output
    return $LayoutObject->Output(
        TemplateFile => 'AgentTicketCompose',
        Data         => {
            FormID => $Self->{FormID},
            %Param,
        },
    );
}

sub _GetFieldsToUpdate {
    my ( $Self, %Param ) = @_;

    my @UpdatableFields;

    # set the fields that can be updatable via AJAXUpdate
    if ( !$Param{OnlyDynamicFields} ) {
        @UpdatableFields = qw( StateID );
    }

    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $IsACLReducible = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->HasBehavior(
            DynamicFieldConfig => $DynamicFieldConfig,
            Behavior           => 'IsACLReducible',
        );
        next DYNAMICFIELD if !$IsACLReducible;

        push @UpdatableFields, 'DynamicField_' . $DynamicFieldConfig->{Name};
    }

    return \@UpdatableFields;
}

# KIX4OTRS-capeIT
sub _GetShownDynamicFields {
    my ( $Self, %Param ) = @_;

    # use only dynamic fields which passed the acl
    my %TicketAclFormData = $Kernel::OM->Get('Kernel::System::Ticket')->TicketAclFormData();

    # get config of frontend module
    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle through dynamic fields to get shown or hidden fields
    for my $DynamicField ( @{$DynamicField} ) {

        # if field was not configured initially set it as not visible
        if ( $Self->{NotShownDynamicFields}->{ $DynamicField->{Name} } ) {
            $DynamicField->{Shown} = 0;
        }
        else {

            # hide DynamicFields only if we have ACL's
            if (
                IsHashRefWithData( \%TicketAclFormData )
                && defined $TicketAclFormData{ $DynamicField->{Name} }
                )
            {
                if ( $TicketAclFormData{ $DynamicField->{Name} } >= 1 ) {
                    $DynamicField->{Shown} = 1;
                }
                else {
                    $DynamicField->{Shown} = 0;
                }
            }

            # else show them by default
            else {
                $DynamicField->{Shown} = 1;
            }
        }
    }

    return 1;
}

# EO KIX4OTRS-capeIT

1;
