        [% IF item_action_ignore AND num_items == 0 %]
            No items were found during staging
            <input type ="hidden" name="item_action" value="ignore">
        [% ELSE %]
            <select name="item_action" id="item_action">
            [% IF ( item_action_always_add ) %]
                <option value="always_add" selected="selected">
            [% ELSE %]
                <option value="always_add">
            [% END %]
                Always add items</option>
            [% IF ( item_action_add_only_for_matches ) %]
                <option value="add_only_for_matches" selected="selected">
            [% ELSE %]
                <option value="add_only_for_matches">
            [% END %]
                Add items only if matching record was found</option>
            [% IF ( item_action_add_only_for_new ) %]
                <option value="add_only_for_new" selected="selected">
            [% ELSE %]
                <option value="add_only_for_new">
            [% END %]
                Add items only if no matching record was found</option>
            [% IF ( item_action_replace ) %]
                <option value="replace" selected="selected">
            [% ELSE %]
                <option value="replace">
            [% END %]
                Replace matching items if any matching record was found (only for existing items)</option>
            [% IF ( item_action_replace_if_bib_match ) %]
                <option value="replace_if_bib_match" selected="selected">
            [% ELSE %]
                <option value="replace_if_bib_match">
            [% END %]
                Replace matching items if matching item is on matching record (only for existing items)</option>
            [% IF ( item_action_ignore ) %]
                <option value="ignore" selected="selected">
            [% ELSE %]
                <option value="ignore">
            [% END %]
                Ignore items</option>
            </select>
        [% END %]
