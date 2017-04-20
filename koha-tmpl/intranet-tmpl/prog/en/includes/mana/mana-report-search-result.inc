[% USE KohaDates %]
[% USE Koha %]
[% USE AuthorisedValues %]
[% USE Branches %]

[% IF statuscode == "200" AND reports %]
    <table id="mana_results_datatable" width=100%>
        <thead>
            <tr>
                <th>Report Name</th>
                <th class="anti-the" width=35%>Notes</th>
                <th>Type</th>
                <th title="number of libraries using this pattern"># of users</th>
                <th class="title-string" title="last time a library used this pattern">Last import</th>
                <th> Comments </th>
                [% UNLESS search_only %]
                  <th class="NoSort">Actions</th>
                [% END %]
            </tr>
        </thead>
        <tbody>
            [% FOREACH report IN reports %]
                [% UNLESS report.cannotdisplay %]
                    [% IF report.nbofcomment > highWarned %]
                  <tr id="row[% report.id %]" class = "high-warned-row">
                    [% ELSIF report.nbofcomment > warned %]
                  <tr id="row[% report.id %]" class = "warned-row">
                    [% ELSIF report.nbofcomment > lowWarned %]
                  <tr id="row[% report.id %]" class = "highlighted-row">
                    [% END %]
                    <input hidden class="rowid" value="[% report.id %]">
                    <td>[% IF ( report.report_name ) %][% report.report_name %][% END %]</td>
                    <td title="[% report.savedsql %]"><div>
                        [% IF report.notes.length > 200 %]
                            [% report.notes.substr(0,200) %]<a class="showbutton">Show More</a></div><div hidden>
                        [% END %]
                            [% report.notes %]
                        [% IF report.notes.length > 200 %]
                                <a class="hidebutton">Show Less</a></div> </td>
                        [% END %]
                    <td> [% report.type %] </td>
                    <td>[% IF ( report.nbofusers ) %][% report.nbofusers %][% END %]</td>
                    <td><span title="[% report.lastimport %]">[% report.lastimport | $KohaDates %]</span></td>
                    <td>[% FOREACH comment IN report.comments %][% comment.message %] ([% comment.nb %]) <br>[% END %]</td>

                    [% UNLESS search_only %]
                        <td>
                            <button onclick="mana_use([% report.id %])"> <i class="fa fa-inbox"></i> Use</button>
                            <input hidden type="text" id="selectedcomment">
                            <select>
                                <option selected disabled>Report mistake</option>
                                [% FOREACH comment IN report.comments %]
                                    <option class="actionreport1" value="[% comment.id %]" onclick="mana_increment('[% comment.id %]', 'resource_comment', 'nb')"> [% comment.message %] ([% comment.nb %])
                                [% END %]
                                    <option data-toggle="modal" onclick="($('#selected_id').val($('.rowid').val()))" data-target="#comment_box"> other
                            </select>
                            <button hidden class="actionreport2" hidden> Cancel</button>
                        </td>
                    [% END %]
                  </tr>
                [% END %]
            [% END %]
        </tbody>
    </table>
[% ELSE %]
    <h4> [% msg %]  statuscode: [% statuscode %]</h4>
[% END %]

<div id="comment_box" class="modal" tabindex="-1" role="dialog" aria-labelledby="mana_search_result_label" style="display: none;">
    <div class="modal-dialog modal-lg" style="width: 30%">
        <div class="modal-content" style="">
            <div class="modal-header">
                <button type="button" id="commentCloseButton" class="closebtn"  aria-hidden="true">×</button>
                <h3 id="mana_submit_comment"> Please enter a new commment (max 35 caracters)</h3>
            </div>
            <div class="modal-body">
                <form>
                    <input hidden id="selected_id" value="">
                    <input type="text" id="manamsg">
                </form>
                <button id="CommentButton"> Comment </button>
            </div>
        </div>
    </div>
</div>
