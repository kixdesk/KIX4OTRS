// --
// Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
// KIX4OTRS-Extensions Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
//
// written/edited by:
//   Dorothea(dot)Doerffel(at)cape(dash)it(dot)de
//
// --
// $Id$
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};

/**
 * @namespace Core.AJAX
 * @memberof Core
 * @author OTRS AG
 * @description
 *      This namespace contains the functionality for AJAX calls.
 */
Core.AJAX = (function (TargetNS) {
    /**
     * @private
     * @name AJAXLoaderPrefix
     * @memberof Core.AJAX
     * @member {String}
     * @description
     *      AJAXLoaderPrefix
     */
    var AJAXLoaderPrefix = 'AJAXLoader',
    /**
     * @private
     * @name ActiveAJAXCalls
     * @memberof Core.AJAX
     * @member {Object}
     * @description
     *      ActiveAJAXCalls
     */
        ActiveAJAXCalls = {};

    if (!Core.Debug.CheckDependency('Core.AJAX', 'Core.Exception', 'Core.Exception')) {
        return;
    }

    if (!Core.Debug.CheckDependency('Core.AJAX', 'Core.App', 'Core.App')) {
        return;
    }

    /**
     * @private
     * @name ToggleAJAXLoader
     * @memberof Core.AJAX
     * @function
     * @param {String} FieldID - Id of the field which is updated via ajax
     * @param {Boolean} Show - Show or hide the AJAX loader image
     * @description
     *      Shows and hides an ajax loader for every element which is updates via ajax.
     */
    function ToggleAJAXLoader(FieldID, Show) {
        var $Element = $('#' + FieldID),
            $Loader = $('#' + AJAXLoaderPrefix + FieldID),
            LoaderHTML = '<span id="' + AJAXLoaderPrefix + FieldID + '" class="AJAXLoader"></span>';

        // Ignore hidden fields
        if ($Element.is('[type=hidden]')) {
            return;
        }
        // Element not present, reset counter and ignore
        if (!$Element.length) {
                ActiveAJAXCalls[FieldID] = 0;
                return;
        }

        // Init counter value, if needed.
        // This counter stores the number of running AJAX requests for each field.
        // The loader image will be shown if it is > 0.
        if (typeof ActiveAJAXCalls[FieldID] === 'undefined') {
            ActiveAJAXCalls[FieldID] = 0;
        }

        // Calculate counter
        if (Show) {
            ActiveAJAXCalls[FieldID]++;
        }
        else {
            ActiveAJAXCalls[FieldID]--;
            if (ActiveAJAXCalls[FieldID] <= 0) {
                ActiveAJAXCalls[FieldID] = 0;
            }
        }

        // Show or hide the loader
        if (ActiveAJAXCalls[FieldID] > 0) {
            if (!$Loader.length) {
                $Element.after(LoaderHTML);
            }
            else {
                $Loader.show();
            }
        }
        else {
            $Loader.hide();
        }
    }

    // KIX4OTRS-capeIT
    /**
     * @private
     * @param
     * @description Disables form to prevent submit during AJAX updates
     */
    function ToggleAJAXForm($FormElement) {
        if (!$FormElement.hasClass('AlreadyDisabled')) {
            Core.Form.DisableForm($FormElement);
        } else {
            Core.Form.EnableForm($FormElement);
        }
    }
    // EO KIX4OTRS-capeIT

    /**
     * @private
     * @name erializeData
     * @memberof Core.AJAX
     * @function
     * @returns {String} Query string of the data.
     * @param {Object} Data - The data that should be converted
     * @description
     *      Converts a given hash into a query string.
     */
    function SerializeData(Data) {
        var QueryString = '';
        $.each(Data, function (Key, Value) {
            QueryString += ';' + encodeURIComponent(Key) + '=' + encodeURIComponent(Value);
        });
        return QueryString;
    }

    /**
     * @private
     * @name AddDebugInformation
     * @memberof Core.AJAX
     * @function
     * @returns {String} Error message with added debug information
     * @param {String} ErrorMessage - The original error message to be extended
     * @param {Object} XHRObject - The original XHRObject from the ajax request
     * @description
     *      Adds some debug response information to the error message and tries to show
     *      a dialog with this information to allow seeing all debug data (browser alert will truncate).
     */
    function AddDebugInformation(ErrorMessage, XHRObject) {

        if (Core.Config.Get('AjaxDebug') && typeof XHRObject === 'object') {
            ErrorMessage += "\n\nResponse status: " + XHRObject.status + " (" + XHRObject.statusText + ")\n";
            ErrorMessage += "Response headers: " + XHRObject.getAllResponseHeaders() + "\n";
            ErrorMessage += "Response content: " + XHRObject.responseText;
        }
        return ErrorMessage;
    }

    /**
     * @private
     * @name GetSessionInformation
     * @memberof Core.AJAX
     * @function
     * @returns {Object} Hash with session data, if needed.
     * @description
     *      Collects session data in a hash if available.
     */
    function GetSessionInformation() {
        var Data = {};
        if (!Core.Config.Get('SessionIDCookie')) {
            Data[Core.Config.Get('SessionName')] = Core.Config.Get('SessionID');
            Data[Core.Config.Get('CustomerPanelSessionName')] = Core.Config.Get('SessionID');
        }
        Data.ChallengeToken = Core.Config.Get('ChallengeToken');
        return Data;
    }

    /**
     * @private
     * @name GetAdditionalDefaultData
     * @memberof Core.AJAX
     * @function
     * @returns {Object} Hash with additional session and action data.
     * @description
     *      Collects additional data that are needed for the ajax requests.
     */
    // KIX4OTRS-capeIT
    // function GetAdditionalDefaultData() {
    function GetAdditionalDefaultData(Action) {
        // EO KIX4OTRS-capeIT
        var Data = {};
        Data = GetSessionInformation();
        // KIX4OTRS-capeIT
        if (!Action)
            Data.Action = Core.Config.Get('Action');
        else
            Data.Action = Action
        // EO KIX4OTRS-capeIT
        return Data;
    }

    /**
     * @private
     * @name UpdateTicketAttachments
     * @memberof Core.AJAX
     * @function
     * @param {Object} Value - Array of hashes, each hash have the needed attachment information.
     * @description
     *      Removes all shown attachments on the screen and adds the ones that are sent in
     *      the Value parmeter.
     */
    function UpdateTicketAttachments(Value) {
        var DeleteText = Core.Config.Get('Localization.Delete'),
            FileID,
            ButtonStrg,
            InputStrg;

        // sync the attachment list with the attachments in the UploadCache
        // 1st: delete the current attachment list
        $('#FileUpload').parent().siblings('li').remove();

        // 2nd: add all files based on the metadata from Value
        $(Value).each(function() {
            FileID = this.FileID;
            ButtonStrg = '<button type="button" id="AttachmentDeleteButton' + FileID + '" name="AttachmentDeleteButton' + FileID + '" value="Delete" class="SpacingLeft">' + DeleteText + '</button>';
            InputStrg = '<input type="hidden" id="AttachmentDelete' + this.FileID + '" name="AttachmentDelete' + this.FileID + '" />';
            $('#FileUpload').parent().before(
                '<li>' + this.Filename + ' (' + this.Filesize + ')' + ButtonStrg + InputStrg + '</li>'
            );

            //3rd: set form submit and disable validation on attachment delete
            $('#AttachmentDeleteButton' + FileID).bind('click', function () {
                var $Form = $(this).closest('form');
                $(this).next('input[type=hidden]').val(1);
                Core.Form.Validate.DisableValidation($Form);
                $Form.trigger('submit');
            });
        });
    }

    // KIX4OTRS-capeIT
    /**
     * @private
     * @param {Object} Object with data.
     * @return nothing
     * @description deletes data
     */
    function DeleteFormData(Data) {
        if (typeof Data !== 'object') {
            return;
        }
        $.each(Data, function (Key, Value) {
            if (Key == 'FormDisplay') {
                if ( Value ) {
                    $.each( Value, function (Index, Value) {
                        var $Element = $('div.Row_'+Value[0]);
                        if ( Value[1] == "" ) {
                            $Element.children('.Field').children().each(function(){
                                if ( $(this).hasClass('Validate_Required') )
                                    $(this).removeClass('Validate_Required');
                            })
                            $Element.addClass('Hidden');
                        }
                        else {
                            $Element.removeClass('Hidden');
                        }
                    })
                }
            }
        })
        delete Data.DeleteFormData;
    }
    // EO KIX4OTRS-capeIT

    /**
     * @private
     * @name UpdateTextarea
     * @memberof Core.AJAX
     * @function
     * @param {Object} $Element - the field selector.
     * @param {Object} Value - the field value. The keys are the IDs of the fields to be updated.
     * @description
     *      Inserts value in textarea components or RichText editors for the ajax requests.
     */
    function UpdateTextarea($Element, Value) {
        var $ParentBody,
            ParentBody,
            Range,
            StartRange = 0,
            NewPosition = 0;

        if ($Element.length) {
            $ParentBody = $Element;
            ParentBody = $ParentBody[0];

            // add the text to the RichText editor
            if (parent.CKEDITOR && parent.CKEDITOR.instances.RichText) {
                parent.CKEDITOR.instances.RichText.focus();
                window.setTimeout(function () {

                    // In some circumstances, this command throws an error (although inserting the HTML works)
                    // Because the intended functionality also works, we just wrap it in a try-catch-statement
                    try {

                        // set new text
                        parent.CKEDITOR.instances.RichText.setData(Value);
                    }
                    catch (Error) {
                        $.noop();
                    }
                }, 100);
                return;
            }

            // insert body and/or link to textarea (if possible to cursor position otherwise to the top)
            else {

                // Get previously saved cursor position of textarea
                if ($Element.parent().data('Cursor')) {
                    StartRange = parent.$Element.data('Cursor').StartRange;
                }

                // Add new text to textarea
                $ParentBody.val(Value);
                NewPosition = StartRange + Value.length;

                // Jump to new cursor position (after inserted text)
                if (ParentBody.selectionStart) {
                    ParentBody.selectionStart = NewPosition;
                    ParentBody.selectionEnd = NewPosition;
                }
                else if (document.selection) {
                    Range = document.selection.createRange().duplicate();
                    Range.moveStart('character', NewPosition);
                    Range.select();
                }

                return;
            }
        }
        else {
            alert('$JSText{"This window must be called from compose window"}');
            return;
        }
    }

    /**
     * @private
     * @name UpdateFormElements
     * @memberof Core.AJAX
     * @function
     * @param {Object} Data - The new field data. The keys are the IDs of the fields to be updated.
     * @description
     *      Updates the given fields with the given data.
     */
    function UpdateFormElements(Data) {
        if (typeof Data !== 'object') {
            return;
        }
        $.each(Data, function (DataKey, DataValue) {
            var $Element = $('#' + DataKey);

            // special case to update ticket attachments
            if (DataKey === 'TicketAttachments') {
                UpdateTicketAttachments(DataValue);
                return;
            }

            if ((!$Element.length || !DataValue) && !$Element.is('textarea')) {
                return;
            }

            // Select elements
            if ($Element.is('select')) {
                $Element.empty();
                $.each(DataValue, function (Index, Value) {
                    var NewOption = new Option(Value[1], Value[0], Value[2], Value[3]);

                    // Check if option must be disabled.
                    if (Value[4]) {
                        NewOption.disabled = true;
                    }

                    // Overwrite option text, because of wrong html quoting of text content.
                    // (This is needed for IE.)
                    NewOption.innerHTML = Value[1];
                    $Element.append(NewOption);

                });

                // Trigger custom redraw event for InputFields
                if ($Element.hasClass('Modernize')) {
                    $Element.trigger('redraw.InputField');
                }

                return;
            }

            // text area elements like the ticket body
            if ($Element.is('textarea')) {
                UpdateTextarea($Element, DataValue);
                return;
            }

            // KIX4OTRS-capeIT
            // direct container replacing
            else if ($Element.is('div,label,p,li') && DataValue) {
                $Element.html(DataValue);
                return;
            }
            else if ($Element.is('input,textarea')) {
                if ($.isArray(DataValue)) {
                    $.each(DataValue, function(Index, DataValue) {
                        // hide dynamic fields which are marked as disabled
                        if (!($.isArray(DataValue))) {
                            $Element.removeAttr('readonly', 'readonly');
                            $Element.attr('disabled', 'disabled');
                            $('.Row_' + Key).children('div.Field').children().each(function() {
                                if ($(this).hasClass('Validate_Required')) {
                                    $(this).removeClass('Validate_Required');
                                    $(this).removeAttr('aria-required');
                                }
                            });
                            $('.Row_' + Key).css({
                                "display" : "none"
                            }).addClass('hiddenFormField');
                        } else {
                            if ($Element.is('input'))
                                $Element.val(DataValue);
                            if ($Element.is('textarea'))
                                $Element.html(DataValue);
                        }
                    });
                } else {
                    if ($Element.is('input'))
                        $Element.val(DataValue);
                    // KIX4OTRS-capeIT
                    // text area elements like the ticket body
                    if ($Element.is('textarea')) {
                        UpdateTextarea($Element, DataValue);
                        return;
                    }
                    // EO KIX4OTRS-capeIT
                }
                return;
            }
            // EO KIX4OTRS-capeIT
            // Other form elements
            $Element.val(DataValue);

            // Trigger custom redraw event for InputFields
            if ($Element.hasClass('Modernize')) {
                $Element.trigger('redraw.InputField');
            }
        });
    }

    /**
     * @private
     * @name RedirectAfterSessionTimeOut
     * @memberof Core.AJAX
     * @function
     * @returns {Boolean} Returns false, if Redirect is not necessary.
     * @param {Object} XHRObject - The original AJAX object.
     * @description
     *      Checks if session is timed out and redirects to the login to avoid
     *      ajax errors.
     */
    function RedirectAfterSessionTimeOut(XHRObject) {
        var Headers = XHRObject.getAllResponseHeaders(),
            OldUrl = location.href,
            NewUrl = Core.Config.Get('Baselink') + "RequestedURL=" + encodeURIComponent(OldUrl);

        if (Headers.match(/X-OTRS-Login: /)) {
            location.href = NewUrl;
            return true;
        }

        return false;
    }

    /**
     * @name SerializeForm
     * @memberof Core.AJAX
     * @function
     * @returns {String} The query string.
     * @param {jQueryObject} $Element - The jQuery object of the form  or any element within this form that should be serialized
     * @param {Object} [Ignore] - Elements (Keys) which should not be included in the serialized form string (optional)
     * @description
     *      Serializes the form data into a query string.
     */
    TargetNS.SerializeForm = function ($Element, Ignore) {
        var QueryString = "";
        if (typeof Ignore === 'undefined') {
            Ignore = {};
        }
        if (isJQueryObject($Element) && $Element.length) {
            $Element.closest('form').find('input:not(:file), textarea, select').filter(':not([disabled=disabled])').each(function () {
                var Name = $(this).attr('name') || '';

                // only look at fields with name
                // only add element to the string, if there is no key in the data hash with the same name
                if (!Name.length || typeof Ignore[Name] !== 'undefined'){
                    return;
                }

                if ($(this).is(':checkbox, :radio')) {
                    if ($(this).is(':checked')) {
                        QueryString += encodeURIComponent(Name) + '=' + encodeURIComponent($(this).val() || 'on') + ";";
                    }
                }
                else if ($(this).is('select')) {
                    $.each($(this).find('option:selected'), function(){
                        QueryString += encodeURIComponent(Name) + '=' + encodeURIComponent($(this).val() || '') + ";";
                    });
                }
                else {
                    QueryString += encodeURIComponent(Name) + '=' + encodeURIComponent($(this).val() || '') + ";";
                }
            });
        }
        return QueryString;
    };

    /**
     * @name FormUpdate
     * @memberof Core.AJAX
     * @function
     * @returns {Object} The jqXHR object.
     * @param {jQueryObject} $EventElement - The jQuery object of the element(s) which are included in the form that should be submitted.
     * @param {String} Subaction - The subaction parameter for the perl module.
     * @param {String} ChangedElement - The name of the element which was changed by the user.
     * @param {Object} FieldsToUpdate - DEPRECATED.
     *                      This used to be the names of the fields that should be updated with the server answer,
     *                      but is not needed any more and will be removed in a future version of OTRS.
     * @param {Function} [SuccessCallback] Callback function to be executed on AJAX success (optional).
     * @param {String} Action The action parameter from the perl module (KIX4OTRS)
     * @param {Boolean} async Optional, defines if this is a asynchronous call (true default) or synchronous (false) (KIX4OTRS)
     * @description
     *      Submits a special form via ajax and updates the form with the data returned from the server
     */
    // KIX4OTRS-capeIT
    // TargetNS.FormUpdate = function ($EventElement, Subaction, ChangedElement, FieldsToUpdate, SuccessCallback) {
    TargetNS.FormUpdate = function($EventElement, Subaction, ChangedElement, FieldsToUpdate, SuccessCallback, Action, Async) {
        // EO KIX4OTRS-capeIT
        var URL = Core.Config.Get('Baselink'),
        // KIX4OTRS-capeIT
        // Data = GetAdditionalDefaultData(),
        Data = GetAdditionalDefaultData(Action),
        // EO KIX4OTRS-capeIT
        QueryString;

        // KIX4OTRS-capeIT
        if ( $EventElement.attr('id') == 'KIXSidebarDynamicFieldEdit' ) {
            Data.Action = 'KIXSidebarDynamicFieldAJAXHandler';
        }
        // EO KIX4OTRS-capeIT

        Data.Subaction = Subaction;
        Data.ElementChanged = ChangedElement;
        QueryString = TargetNS.SerializeForm($EventElement, Data) + SerializeData(Data);

        if (FieldsToUpdate) {
            $.each(FieldsToUpdate, function (Index, Value) {
                ToggleAJAXLoader(Value, true);
            });
        }

        // KIX4OTRS-capeIT
        ToggleAJAXForm($EventElement);
        // EO KIX4OTRS-capeIT

        return $.ajax({
            type: 'POST',
            url: URL,
            data: QueryString,
            dataType: 'json',
            // KIX4OTRS-capeIT
            async : (typeof Async === 'undefined') ? true : Async,
            // EO KIX4OTRS-capeIT
            success: function (Response, Status, XHRObject) {
                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                if (!Response) {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError("Invalid JSON from: " + URL, 'CommunicationError'));
                }
                else {
                    // KIX4OTRS-capeIT
                    DeleteFormData(Response);
                    // EO KIX4OTRS-capeIT
                    UpdateFormElements(Response,$EventElement);
                    if (typeof SuccessCallback === 'function') {
                        SuccessCallback();
                    }
                    Core.App.Publish('Event.AJAX.FormUpdate.Callback', [Response]);
                }
            },
            complete: function () {
                if (FieldsToUpdate) {
                    $.each(FieldsToUpdate, function (Index, Value) {
                        ToggleAJAXLoader(Value, false);
                    });
                }
                // KIX4OTRS-capeIT
                ToggleAJAXForm($EventElement);
                // EO KIX4OTRS-capeIT
            },
            error: function (XHRObject, Status, Error) {

                var ErrorMessage = "Error during AJAX communication. Status: " + Status + ", Error: " + Error;

                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                ErrorMessage = AddDebugInformation(ErrorMessage, XHRObject);

                if (Status !== 'abort') {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError(ErrorMessage, 'CommunicationError'));
                }
            }
        });
    };

    /**
     * @name ContentUpdate
     * @memberof Core.AJAX
     * @function
     * @returns {Object} The jqXHR object.
     * @param {jQueryObject} $ElementToUpdate - The jQuery object of the element(s) which should be updated
     * @param {String} URL - The URL which is called via Ajax
     * @param {Function} Callback - The additional callback function which is called after the request returned from the server
     * @description
     *      Calls an URL via Ajax and updates a html element with the answer html of the server.
     */
    // KIX4OTRS-capeIT
    // TargetNS.ContentUpdate = function ($ElementToUpdate, URL, Callback) {
    TargetNS.ContentUpdate = function ($ElementToUpdate, URL, Callback, Async) {
    // EO KIX4OTRS-capeIT
        var QueryString, QueryIndex = URL.indexOf("?"), GlobalResponse;

        if (QueryIndex >= 0) {
            QueryString = URL.substr(QueryIndex + 1);
            URL = URL.substr(0, QueryIndex);
        }
        QueryString += SerializeData(GetSessionInformation());

        return $.ajax({
            type: 'POST',
            url: URL,
            data: QueryString,
            dataType: 'html',
            // KIX4OTRS-capeIT
            async : (typeof Async === 'undefined') ? true : Async,
            // EO KIX4OTRS-capeIT
            success: function (Response, Status, XHRObject) {
                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                if (!Response) {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError("No content from: " + URL, 'CommunicationError'));
                }
                else if ($ElementToUpdate && isJQueryObject($ElementToUpdate) && $ElementToUpdate.length) {
                    GlobalResponse = Response;
                    $ElementToUpdate.html(Response);
                }
                else {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError("No such element id: " + $ElementToUpdate.attr('id') + " in page!", 'CommunicationError'));
                }
            },
            complete: function () {
                if ($.isFunction(Callback)) {
                    Callback();
                }
                Core.App.Publish('Event.AJAX.ContentUpdate.Callback', [GlobalResponse]);
            },
            error: function (XHRObject, Status, Error) {

                var ErrorMessage = "Error during AJAX communication. Status: " + Status + ", Error: " + Error;

                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                if (Status !== 'abort') {

                    ErrorMessage = AddDebugInformation(ErrorMessage, XHRObject);

                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError(ErrorMessage, 'CommunicationError'));
                }
            }
        });
    };

    /**
     * @name FunctionCall
     * @memberof Core.AJAX
     * @function
     * @returns {Object} The jqXHR object.
     * @param {String} URL - The URL which is called via Ajax.
     * @param {Object} Data - The data hash or data query string.
     * @param {Function} Callback - The callback function which is called after the request returned from the server.
     * @param {String} [DataType=json] Defines the datatype, default 'json', could also be 'html'
     * @description
     *      Calls an URL via Ajax and executes a given function after the request returned from the server.
     */
    // KIX4OTRS-capeIT
    // TargetNS.FunctionCall = function (URL, Data, Callback, DataType) {
    TargetNS.FunctionCall = function(URL, Data, Callback, DataType, Async) {
    // EO KIX4OTRS-capeIT

        if (typeof Data === 'string') {
            Data += SerializeData(GetSessionInformation());
        } else {
            Data = $.extend(Data, GetSessionInformation());
        }

        return $.ajax({
            type: 'POST',
            url: URL,
            data: Data,
            dataType: (typeof DataType === 'undefined') ? 'json' : DataType,
            // KIX4OTRS-capeIT
            async : (typeof Async === 'undefined') ? true : Async,
            // EO KIX4OTRS-capeIT
            success: function (Response, Status, XHRObject) {
                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                // call the callback
                if ($.isFunction(Callback)) {
                    Callback(Response);
                    // publish to event channel
                    Core.App.Publish('Event.AJAX.FunctionCall.Callback', [Response]);
                }
                else {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError("Invalid callback method: " + ((typeof Callback === 'undefined') ? 'undefined' : Callback.toString())));
                }
            },
            error: function (XHRObject, Status, Error) {

                var ErrorMessage = "Error during AJAX communication. Status: " + Status + ", Error: " + Error;

                if (RedirectAfterSessionTimeOut(XHRObject)) {
                    return false;
                }

                ErrorMessage = AddDebugInformation(ErrorMessage, XHRObject);

                // We sometimes manually abort an ajax request (e.g. in autocompletion). This should not throw a global error message
                if (Status !== 'abort') {
                    // We are out of the OTRS App scope, that's why an exception would not be caught. Therefore we handle the error manually.
                    Core.Exception.HandleFinalError(new Core.Exception.ApplicationError(ErrorMessage, 'CommunicationError'));
                }
            }
        });
    };

    return TargetNS;
}(Core.AJAX || {}));
