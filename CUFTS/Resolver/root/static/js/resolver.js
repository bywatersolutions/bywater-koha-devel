$(document).ready( function() {

    $('.results-others-available').one('click', function() {
        $(this).parent().find('li.other-results').removeClass('hidden-result');
        $(this).hide();
    });

    $('.parallel-holdings').each( function(index) {
        var holdings_div = $(this);
        var holdings_table = holdings_div.find('table').first();
        var resource_id = holdings_div.attr('resource');
        if ( typeof CUFTS_Resolver !== 'object' || !CUFTS_Resolver.hasOwnProperty('resources') || !CUFTS_Resolver.resources.hasOwnProperty(resource_id) ) {
            holdings_div.text('Parallel holdings search not configured correctly.');
            return;
        }
        var resource_data = CUFTS_Resolver.resources[resource_id];

        // holdings_table.append(
        //     $('<tr>')
        //         .append( $('<th>').text('Location') )
        //         .append( $('<th>').text('Holdings') )
        // );

        for (var index = 0; index < resource_data.monograph_searches.length; ++index) {
            var search_data = resource_data.monograph_searches[index];
            var search_data_id = search_data.id;
            resource_data.monograph_searches_total += 1;

            var location_td = $('<td>').addClass('location').text(search_data.name);
            var holdings_td = $('<td>').addClass('holdings').html( $('<dl class="dl-horizontal"><dt>Status</dt><dd><span>Searching</span> <i class="spinner"></i></dd></dl>') );

            holdings_table.append( $('<tr>').attr('id', search_data_id).append( location_td ).append( holdings_td ) );

            $.ajax({
                url: search_data.url,
                dataType: 'json',
                success: create_ajax_success(search_data_id),
                error: create_ajax_error(search_data_id),
            });
        }

    });

    function create_ajax_success(search_id) {
        return function(data) {
            var holdings_block = $('#' + search_id + ' .holdings');
            // resource_data.monograph_searches_completed += 1;
            if ( data.total_results == 0 ) {
                holdings_block.text( 'No holdings found.' );
            }
            else if ( data.total_results > 2 ) {
                holdings_block.text( 'Too many matching results found: ' + data.total_results );
            }
            else {
                holdings_block.empty();
                for ( var results_index = 0; results_index < data.results.length; results_index++ ) {
                    var result = data.results[results_index];

                    var dl = $('<dl/>').addClass('dl-horizontal');

                    if ( result.title ) {
                        dl.append(
                            $('<dt/>').text( 'Title' ),
                            $('<dd/>').text( result.title )
                        );
                    }

                    if ( result.isbn ) {
                        dl.append(
                            $('<dt/>').text( 'ISBN' ),
                            $('<dd/>').text( result.isbn )
                        );
                    }

                    if ( result.call_number ) {
                        dl.append(
                            $('<dt/>').text( 'Call Number' ),
                            $('<dd/>').text( result.call_number )
                        );
                    }

                    if ( result.fulltext ) {
                        dl.append(
                            $('<dt/>').text( 'Fulltext' ),
                            $('<dd/>').append(
                                $('<a/>').attr('href', result.url ).text('Available online')
                            )
                        );
                    }

                    if ( jQuery.isArray(result.availability) && result.availability.length ) {
                        dl.append( $('<dt/>').text( 'Print' ) );
                        for ( var avail_index = 0; avail_index < result.availability.length; ++avail_index ) {
                            var avail = result.availability[avail_index];
                            dl.append(
                                $('<dd/>').append(
                                    $('<a/>').attr('href', avail.url ).text(avail.holdings)
                                )
                            );
                        }
                    }

                    holdings_block.append(dl);
                }
            }
        }
    }

    function create_ajax_error(search_id) {
        return function(data) {
            console.log(search_id);
            // resource_data.monograph_searches_failed += 1;
            $('#' + search_id + ' .holdings').html( 'Failed' );
        }
    }


});
