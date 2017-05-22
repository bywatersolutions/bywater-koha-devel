[% INCLUDE 'blocking_errors.inc' %]
<div id="toolbar" class="btn-toolbar">
    [% IF ( CAN_user_reports_create_reports ) %]
        <div class="btn-group">
            <button class="btn btn-default btn-sm dropdown-toggle" data-toggle="dropdown"><i class="fa fa-plus"></i> New report <span class="caret"></span></button>
            <ul class="dropdown-menu">
                <li id="newmenuc"><a href="/cgi-bin/koha/reports/guided_reports.pl?phase=Build%20new">New guided report</a> </li>
                <li id="newsql"><a href="/cgi-bin/koha/reports/guided_reports.pl?phase=Create%20report%20from%20SQL">New SQL report</a> </li>
                [% IF Koha.Preference('Mana')==1 %]
                <li id="newsql"><a href="" data-toggle="modal" data-target="#mana_search_result">New SQL from Mana</a> </li>
                [% END %]
            </ul>
        </div>
    [% END %]

    [% IF ( showsql || execute || editsql || save_successful ) %]
        [% IF ( CAN_user_reports_create_reports ) %]
            [% UNLESS ( editsql ) # Do not show edit button on edit page %]
                <div class="btn-group">
                    <a id="editreport" class="btn btn-default btn-sm" href="/cgi-bin/koha/reports/guided_reports.pl?reports=[% id | html %]&amp;phase=Edit%20SQL">
                        <i class="fa fa-pencil"></i> Edit
                    </a>
                </div>
            [% END %]
            <div class="btn-group">
                <a class="btn btn-default btn-sm" title="Duplicate this saved report" href="/cgi-bin/koha/reports/guided_reports.pl?phase=Create report from SQL&amp;sql=[% original_sql || sql |uri %]&amp;reportname=[% reportname |uri %]&amp;notes=[% notes |uri %]">
                    <i class="fa fa-copy"></i> Duplicate
                </a>
            </div>
        [% END %]

        [% IF ( CAN_user_reports_delete_reports ) %]
            <div class="btn-group">
                <a class="delete btn btn-default btn-sm" href="/cgi-bin/koha/reports/guided_reports.pl?reports=[% id | html %]&phase=Delete%20Saved">
                    <i class="fa fa-trash"></i> Delete
                </a>
            </div>
        [% END %]

        [% UNLESS ( errors ) # Unless there are errors saving a report %]
            <div class="btn-group">
                <a id="runreport" class="btn btn-default btn-sm" href="/cgi-bin/koha/reports/guided_reports.pl?reports=[% id | html %]&amp;phase=Run%20this%20report">
                    <i class="fa fa-play"></i> Run report
                </a>
            </div>
            <div class="btn-group">
                <a class="btn btn-default btn-sm" href="/cgi-bin/koha/tools/scheduler.pl?id=[% id | html %]">
                    <i class="fa fa-clock-o"></i> Schedule
                </a>
            </div>
        [% END %]

        [% IF ( execute ) %]
            [% BLOCK params %]
                [%- FOREACH param IN sql_params %]&amp;sql_params=[% param | uri %][% END %]
                    [%- FOREACH param_name IN param_names %]&amp;param_name=[% param_name | uri %][% END %]
            [%- END %]


            <div class="btn-group">
                <button class="btn btn-default btn-sm dropdown-toggle" data-toggle="dropdown" id="format"><i class="fa fa-upload"></i> Download <span class="caret"></span></button>
                <ul class="dropdown-menu">
                    <li><a id="csv" href="/cgi-bin/koha/reports/guided_reports.pl?reports=1&phase=Export&amp;format=csv&amp;report_id=[% id | html %]&amp;reportname=[% name |uri %][% PROCESS params %]">[% PROCESS 'delimiter_text.inc' %]</a></li>
                    <li><a id="tab" href="/cgi-bin/koha/reports/guided_reports.pl?reports=1&phase=Export&amp;format=tab&amp;report_id=[% id | html %]&amp;reportname=[% name |uri %][% PROCESS params %]">Tab separated text</a></li>
                    <li><a id="ods" href="/cgi-bin/koha/reports/guided_reports.pl?reports=1&phase=Export&amp;format=ods&amp;report_id=[% id | html %]&amp;reportname=[% name |uri %][% PROCESS params %]">Open Document Spreadsheet</a></li>
                    [% IF (results.json) %]
                        <li><a id="download-chart" href="#">Chart (.svg)</a></li>
                    [% END %]
                </ul>
            </div>
            <div class="btn-group">
                <a class="btn btn-default btn-sm toggle_sql" id="toggle_sql_hid" href="#"><i class="fa fa-eye"></i> Show SQL code</a>
                <a class="btn btn-default btn-sm toggle_sql" id="toggle_sql_vis" href="#" style="display:none;"><i class="fa fa-eye-slash"></i> Hide SQL code</a>
            </div>
            <div class="btn-group">
                <a class="btn btn-default btn-sm toggle_chart_settings" id="toggle_chart_settings_hid" href="#"><i class="fa fa-eye"></i> Show chart settings</a>
                <a class="btn btn-default btn-sm toggle_chart_settings" id="toggle_chart_settings_vis" href="#" style="display:none;"><i class="fa fa-eye-slash"></i> Hide chart settings</a>
            </div>
        [% END %]

    [% END %]
</div>

[% IF Koha.Preference('Mana')==1 %]
    <div id="mana_search_result" class="modal fade container-fluid" tabindex="-1" role="dialog" aria-labelledby="mana_search_result_label" style="width: 100%; left:0%; margin-left: auto; display: none;">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <button type="button" class="closebtn" data-dismiss="modal" aria-hidden="true">×</button>
                    <h3 id="mana_search_result_label"> Mana Search</h3>
                </div>
                <div>
                    <form id="search_form" style="margin-left: 5%">
                        Please enter a few key words:
                        <input type=text id=mana_search_field>
                        <input type=button class="mana_search_button" value="Search">
                    </form>
                    <div class="modal-body">
                    </div>
                </div>
            </div>
        </div>
    </div>
[% END %]

<script type="text/javascript">
    $(document).ready( function(){
        $(".mana_search_button").on("click",function(){
            mana_search($("#mana_search_field").val());
        });
    });

    $('#search_form').on( "submit", function(event) {
        event.preventDefault();
        mana_search($(this).children("#mana_search_field").val());
    });

    function mana_increment(mana_id, resourcename, fieldvalue, stepvalue = 1){
        $.ajax( {
            type: "POST",
            url: "/cgi-bin/koha/svc/mana/addvaluetofield",
            data: {id: mana_id, field: fieldvalue, resource: resourcename, step: stepvalue},
            datatype: "json",
        }).done( function() {
        }).fail( function(){ alert("") });
    }

    function mana_use( mana_id ){
        $.ajax( {
            type:"POST",
            url: "/cgi-bin/koha/svc/mana/use",
            data: {id:mana_id, resource: 'report', saveinbase: 1},
            dataType: "json",
        })
        .done( function (result){
            if ( result.errmsg ){
                alert( result.errmsg );
            }
            else{
                window.location = ("/cgi-bin/koha/reports/guided_reports.pl?reports=").concat(result.id).concat("&amp;phase=Show%20SQL&mana_success=1&phase=Edit%20SQL");
            }
        })
        .fail( function ( foo, msg, longmsg, bla ){
        });
    }

    function mana_search( textquery ){
        $.ajax({
            type: "POST",
            url: "/cgi-bin/koha/svc/mana/search",
            data: {biblionumber: $("#biblionumber").val(), resource: 'report', id: textquery, usecomments: 1},
            dataType: "html",
        })
        .done( function( result ) {
            $("#mana_search_result .modal-body").html(result);
            $("#mana_search_result_label").text("Results from Mana Knowledge Base");
            $("#mana_results_datatable").dataTable($.extend(true, {}, dataTablesDefaults,{
                "sPaginationType":"four_button",
                "autoWidth": false,
                "columnDefs": [
                    { "width": "35%", "targets": 1 }
                ],
                "aoColumnDefs": [
                    { 'bSortable': false, "bSearchable": false, 'aTargets': [ 'NoSort' ] },
                    { "sType": "title-string", "aTargets" : [ "title-string" ] },
                    { 'sType': "anti-the", 'aTargets' : [ 'anti-the'] }
                ]
            }));
            if($("td.dataTables_empty").length == 0){
                 $("#mana_search").show();
            }

            $( "select[class='actionreport1']" ).show();
            $( "button[class='actionreport2']" ).hide();
            $("#CommentButton").on("click", function(){
                var resource_type = "report";
                var target_id = $("#selected_id").val();
                var manamsg = $("#manamsg").val();
                mana_comment(target_id, manamsg, resource_type);
                $("#comment_box").modal("hide");
            });

            $(".showbutton").on("click", function(){
                $(this).parent().hide();
                $(this).parent().next().show();
            });

            $("a[class='hidebutton']").on("click", function(){
                $(this).parent().hide();
                $(this).parent().prev().show();
            });

            $("#commentCloseButton").on("click", function(){
                $("#comment_box").modal("hide");
            });

            $(".actionreport1").on("click", function(){
                $("#selectedcomment").val($(this).val());
                $(this).parent("select").hide();
                $(this).parent("select").next().show();
            });

            $(".actionreport2").on("click", function(){
                $(this).hide();
                $(this).prev().show();
                mana_increment($("#selectedcomment").val(), 'resource_comment', 'nb', -1);
            });
        }).fail( function( result ){
        });
    }

    function mana_comment( target_id, manamsg, resource_type ){
        $.ajax( {
            type: "POST",
            url: "/cgi-bin/koha/svc/mana/share",
            data: {message: manamsg, resource: resource_type , resource_id: target_id},
            datatype: "json",
        })
    }
</script>
