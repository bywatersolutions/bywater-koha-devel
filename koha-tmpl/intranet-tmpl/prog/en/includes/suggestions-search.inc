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
            "url": "/api/v1/suggestions"
        },
        "stateSave": true,
        "columns": [
            {
                "data": "title",
                "searchable": true,
                "orderable": true,
                "max-width": "20%",
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
                "data": "suggested_by",
                "searchable": true,
                "orderable": true,
            },
            {
                "data": "status",
                "searchable": true,
                "orderable": true,
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
