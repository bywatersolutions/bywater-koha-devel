<div id="suggestion_search_modal" class="modal" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" style="width: 80%">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="closebtn" data-dismiss="modal" aria-hidden="true">x</button>
                <h3 id="search_suggestions_label">
                    Search suggestions for order:
                    <span id="search_suggestion_modal_title"></span>
                </h3>

            </div>
            <div class="modal-body">
                <div class="suggestions_search">
                    <table id="suggestions_search_table" class="wrap">
                        <thead><tr>
                            <th>Title</th>
                            <th>Author</th>
                            <th>ISBN</th>
                            <th>Note</th>
                            <th>Publication info</th>
                            <th>Suggested by</th>
                            <th>Additional info</th>
                            <th>&nbsp;</th>
                        </tr></thead>
                    </table>
                </div>
            </div>
            <div class="modal-footer">
                <a href="#" data-dismiss="modal" aria-hidden="true" class="cancel">Close</a>
            </div>
        </div>
    </div>
</div>

<script>
$(document).ready(function(){

    suggestions_table = $("#suggestions_search_table").kohaTable({
        "ajax": {
            "url": "/api/v1/suggestions?q=[{\"archived\":false}]"
        },
        "embed": ["suggester.library"],
        "stateSave": true,
        "columns": [
            {
                "data": "title",
                "searchable": true,
                "orderable": true,
                "max-width": "20%",
                "render": function( data, type, row, meta ) {
                    let title_row = "";
                    title_row += "<a target=\"_blank\"  href=\"/cgi-bin/koha/suggestion/suggestion.pl?&op=editsuggestionid=" + row.suggestion_id + "\">" ;
                    title_row += row.title ? row.title : ('Suggestion #' + row.suggestion_id) + '</a>';
                    return title_row;
                }
            },
            {
                "data": "author",
                "searchable": true,
                "orderable": true,
            },
            {
                "data": "isbn",
                "searchable": true,
                "orderable": true,
            },
            {
                "data": "note",
                "searchable": true,
                "orderable": true,
            },
            {
                "data": "publisher_code",
                "searchable": true,
                "orderable": true,
            },
            {
                "data": "suggested_by:suggester.firstname:suggester.surname:suggester.library_id",
                "searchable": true,
                "orderable": true,
                "render": function( data, type, row, meta ) {
                    let suggester_info = "";
                    if( row.suggester ){
                        suggester_info += row.suggester.surname;
                        suggester_info += row.suggester.firstname ? (", " + row.suggester.firstname) : "";
                        suggester_info += row.suggester.library ? ("</br> " + row.suggester.library.name + " (" + row.suggester.library_id + ")") : "";
                    }
                    return suggester_info;
                }
            },
            {
                "data": "status:biblionumber",
                "searchable": true,
                "orderable": true,
                "render": function( data, type, row, meta ) {
                    let addl_info = "";
                    if( row.biblio_id > 0 ){
                        addl_info += "Biblionumber: " + row.biblio_id + "</br>";
                    }
                    addl_info += row.status;
                    return addl_info;
                }
            },
            {
                "data": "suggestionid",
                "searchable": false,
                "orderable": false,
                "render": function( data, type, row, meta ) {
                    let modal_title = $("#search_suggestion_modal_title");
                    let import_id = modal_title.data('import_record_id');
                    console.log(row);
                    if( $("input[name^='attach_suggestion_'][value='"+row.suggestion_id+"'").length == 0 ){
                    let add_button = '<a class="btn btn-default btn-xs select_suggestion"';
                    add_button += ' data-suggestionid="' + row.suggestion_id;
                    add_button += '" data-title="' + row.title + ' (' + row.suggestion_id + ')' + '">';
                    add_button += 'Select</a>';
                    return add_button;
                    } else {
                    return '';
                    }
                    },
                },
            ],
        "autoWidth": false,
        }, null, 1);

    console.log(suggestions_table);
});
</script>
