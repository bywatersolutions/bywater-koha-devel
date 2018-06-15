[% USE KohaDates %]
[% USE AuthorisedValues %]
[% SET resolutions = AuthorisedValues.GetAuthValueDropbox('RETURN_CLAIM_RESOLUTION') %]
<div id="relreturn-claims">
    [% IF return_claims.count < 1 %]
        <p>Patron has no return claims.</p>
    [% ELSE %]
        <form method="post" action="/cgi-bin/koha/circ/claims-returned.pl">
            <input type="hidden" name="action" value="resolve" />
            <input type="hidden" name="borrowernumber" value="[% patron.id %]" />
            <input type="hidden" name="destination" value="[% destination %]" />

            <table>
                <thead>
                    <tr>
                         <th>Item</th>
                         <th>Notes</th>
                         <th>Created</th>
                         <th>Updated</th>
                         <th>Resolution</th>
                         [% IF CAN_user_editcatalogue_edit_items %]
                             <th>&nbsp;</th>
                         [% END %]
                    </tr>
                </thead>
                <tbody>
                    [% SET unresolved = 0 %]
                    [% FOREACH r IN return_claims %]
                        <tr>
                            <td>
                                [% r.biblio.title %] ( [% r.item.barcode %] )
                            </td>
                            <td>
                                [% r.notes | html_line_break %]
                                <a id="edit_note_[% r.id %]" class="return-claim-notes-edit" data-claim-id="[% r.id %]" data-claim-note="[% r.notes | html_entity %]"  href="#"><i class="fa fa-edit"></i></a>
                            </td>
                            <td>
                                [% r.created_on | $KohaDates %]
                            </td>
                            <td>
                                [% r.updated_on | $KohaDates %]
                            </td>
                            <td>
                                [% IF r.resolution %]
                                    [% AuthorisedValues.GetByCode( 'RETURN_CLAIM_RESOLUTION', r.resolution ) %]
                                [% ELSE %]
                                    <i>Unresolved</i>
                                [% END %]
                            </td>
                            <td>
                                [% IF CAN_user_editcatalogue_edit_items && ! r.resolution %]
                                    [% SET unresolved = unresolved + 1 %]
                                    [% IF resolutions %]
                                        <input type="hidden" name="id" value="[% r.id %]" />
                                        <label for="resolution_[% r.id %]">Resolution: </label>
                                        <select name="resolution_[% r.id %]" id="resolution_[% r.id %]">
                                            <option value="">-</option>
                                            [% FOREACH res IN resolutions %]
                                                <option value="[% res.authorised_value %]">[% res.lib %]</option>
                                            [% END %]
                                        </select>
                                    [% ELSE %]
                                        &nbsp;
                                    [% END %]
                                [% END %]
                            </td>
                        </tr>
                    [% END %]
                </tbody>
            </table>

            [% IF unresolved > 0 %]
                <fieldset class="action">
                    <button class="btn btn-default"><i class="fa fa-check"></i> Resolve</button>
                </fieldset>
            [% END %]
        </form>
    [% END %]
</div>

<div class="modal" id="claims-returned-notes-modal" tabindex="-1" role="dialog" aria-labelledby="itemSearchFallbackLabel">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form id="claims-returned-notes-modal-form" action="/cgi-bin/koha/circ/claims-returned.pl">
                <input type="hidden" name="borrowernumber" value="[% patron.id %]" />
                <input type="hidden" name="destination"    value="[% destination %]" />
                <input type="hidden" name="action"         value="notes-edit" />
                <input type="hidden" name="id" id="claims-returned-notes-modal-form-id" value="" />

                <div class="modal-header">
                    <button type="button" class="closebtn" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                    <h3 id="claims-returned-notes-modal-label"><h3><i class="fa fa-edit"></i> Edit return claim notes</h3>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label for="claims-returned-notes-modal-form-notes">Notes</label>
                        <textarea id="claims-returned-notes-modal-form-notes" name="notes" class="form-control" rows="3"></textarea>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-default claim-returned" type="submit"><i class="fa fa-save"></i> Save</button>
                    <button class="btn btn-default claim-returned cancel" href="#" data-dismiss="modal" aria-hidden="true"><i class="fa fa-times"></i> Cancel</button>
                </div>
            </form>
        </div>
    </div>
</div>
