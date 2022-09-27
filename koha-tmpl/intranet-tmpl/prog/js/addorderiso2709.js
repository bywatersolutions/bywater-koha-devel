/* global dataTablesDefaults __ */

$(document).ready(function() {
    $("#Aform").preventDoubleFormSubmit();
    $("#files").dataTable($.extend(true, {}, dataTablesDefaults, {
        "aoColumnDefs": [
            { "bSortable": false, "bSearchable": false, 'aTargets': [ 'NoSort' ] },
            { "sType": "anti-the", "aTargets" : [ "anti-the" ] }
        ],
        "sPaginationType": "full",
        "aaSorting": []
    }) );

    $(".add_suggestions").click(function(){
        let the_button = $(this);
        let modal_title = $("#search_suggestion_modal_title");
        modal_title.text( the_button.data('title') );
        modal_title.data('import_record_id',the_button.data('biblionumber') );
        let the_table = $("#suggestions_search_table").DataTable();
        the_table.draw();
        $("#suggestion_search_modal").modal().show();
    });
    $("body").on("click", ".select_suggestion", function(){
        let suggestion_id = $(this).data('suggestionid');
        let import_record_id =  $("#search_suggestion_modal_title").data('import_record_id');
        $("ul#link_suggestions_"+import_record_id).append(`
            <li>
            <input name="attach_suggestion_record_`+import_record_id+`" type="hidden" value="`+suggestion_id+`" >
            <label for="attach_suggestion_record_`+import_record_id+`">Attach suggestion: </label>
            <span>`+$(this).data('title')+`</span>
            <a class="remove_suggestion">Remove</a>
            </li>
        `);
        $(this).remove();
    });
    $("body").on("click", ".remove_suggestion", function(){
        $(this).parent('li').remove();
    });

    checkOrderBudgets();
    var all_budget_id = $("#all_budget_id");

    $("#all_budget_id,[name='budget_id'],.budget_code_item,[name='import_record_id']").on("change", function(){
        checkOrderBudgets();
    });

    $("#records_to_import fieldset.rows div").hide();
    $('input:checkbox[name="import_record_id"]').change(function(){
        var container = $(this).parents("fieldset");
        if ( $(this).is(':checked') ) {
            $(container).addClass("selected");
            $(container).removeClass("unselected");
            $(container).find("div").toggle(true);
        } else {
            $(container).addClass("unselected");
            $(container).removeClass("selected");
            $(container).find("div").toggle(false);
        }
    } );

    $("input:checkbox").prop("checked", false);
    $("div.biblio.unselected select").prop('disabled', false);
    $("div.biblio.unselected input").prop('disabled', false);

    $("#checkAll").click(function(e){
        e.preventDefault();
        $("input:checkbox[name='import_record_id']").prop("checked", true).change();
    });
    $("#unCheckAll").click(function(e){
        e.preventDefault();
        $("input:checkbox[name='import_record_id']").prop("checked", false).change();
    });

    $("input#add_order").on("click", function(e){
        e.preventDefault();

        if ( $("input:checkbox[name='import_record_id']:checked").length < 1 ) {
            alert( __("There is no record selected") );
            return false;
        }

        var error = 0;
        $("input:checkbox[name='import_record_id']:checked").parents('fieldset').find('input[name="quantity"]').each(function(){
            if ( $(this).val().length < 1 || isNaN( $(this).val() ) ) {
                error++;
            }
        });
        if ( error > 0 ) {
            alert(error + " " + __("quantity values are not filled in or are not numbers") );
            return false;

        }

        error = checkOrderBudgets();
        if ( error > 0 ) {
            alert( __("Some budgets are not defined in item records") );
            return false;
        }

        if (0 < CheckMandatorySubfields(this.form)) {
            // Open the item tab
            $('#tabs').tabs('option', 'active', 1);

            alert(__('Some required item subfields are not set'));
            return false;
        }

        disableUnchecked($(this.form));

        $(this.form).submit();
    });

    $(".previewData").on("click", function(e){
        e.preventDefault();
        var ltitle = $(this).text();
        var page = $(this).attr("href");
        $("#dataPreviewLabel").text(ltitle);
        $("#dataPreview .modal-body").load(page + " div");
        $('#dataPreview').modal({show:true});
    });
    $("#dataPreview").on("hidden.bs.modal", function(){
        $("#dataPreviewLabel").html("");
        $("#dataPreview .modal-body").html("<div id=\"loading\"><img src=\"[% interface | html %]/[% theme | html %]/img/spinner-small.gif\" alt=\"\" /> " + __("Loading") + "</div>");
    });
});

function disableUnchecked(){
    $("fieldset.biblio.unselected").each(function(){
        $(this).remove();
    });
    return 1;
}

function checkOrderBudgets(){
    var unset_funds = 0;
    var all_budget_id = $("#all_budget_id");
    // If we don't have an overarching default set we need to check each selected order
    if ( !all_budget_id.val() ) {
        $("fieldset.biblio.rows.selected").each(function(){
            var default_order_fund = $(this).find("[name='budget_id']");
            // For each order we see if budget is set for order
            if( !default_order_fund.val() ){
                $(this).find(".item_fund.required").show();
                //If not we need to check each item on the order
                var item_funds = $(this).find(".budget_code_item");
                if( item_funds.length ){
                    item_funds.each(function(){
                        if( !$(this).val() ){
                            $(this).addClass('required').prop("required", true);
                            unset_funds++;
                        } else {
                            $(this).removeClass('required').prop("required", false);
                        }
                    });
                } else {
                    //If the order has no items defined then the order level fund is required
                    default_order_fund.addClass('required').prop("required", true);
                    $(this).find(".fund span.required").show();
                    $(this).find(".item_fund.required").hide();
                    unset_funds++;
                }
            } else {
                $(this).find(".fund span.required").hide();
                // If fund is set for order then none of the others are required
                $(this).find(".budget_code_item").each(function(){
                    if( !$(this).val() ){
                        $(this).val( default_order_fund.val() );
                        $(this).removeClass('required').prop("required", false);
                    }
                });
                $(this).removeClass('required').prop("required", false);
            }
        });
    } else {
        // Default is set overall, we just need to populate it through
        // to each order/item
        $("[name='budget_id'],.budget_code_item").each(function(){
            if( !$(this).val() ){
                $(this).val( all_budget_id.val() );
                $(this).removeClass('required').prop("required", false);
                $(".item_fund.required").hide();
                $(".fund span.required").hide();
            }
        });
    }
    return unset_funds;
}
