<form id="patron-search-form" class="patron_search_form">
    <fieldset class="brief">
        <h3>[% t("Search for patron") | html %]</h3>
        <ol>
            <li>
                <label for="search-query">[% t("Search:") | html %]</label>
                <input type="text" id="search-query" class="search_patron_filter focus" />
            </li>
            <li>
                <label for="search-field">[% t("Search field:") | html %]</label>
                <select id="search-field">
                    <option value="">[% t("Standard") | html %]</option>
                    <option value="surname">[% t("Surname") | html %]</option>
                    <option value="cardnumber">[% t("Card number") | html %]</option>
                    <option value="email">[% t("All emails") | html %]</option>
                    <option value="phone|mobile">[% t("All phones") | html %]</option>
                    <option value="address|city|postal_code">[% t("Full address") | html %]</option>
                    <option value="date_of_birth">[% t("Date of birth") | html %]</option>
                    <option value="patron_id">[% t("Borrower number") | html %]</option>
                    [% IF Koha.Preference('ExtendedPatronAttributes') %]
                        [% FOREACH attribute IN ExtendedAttributeTypes.all( staff_searchable => 1 ) %]
                            <option value="ext_attr_[% attribute.code | html %]">[% attribute.description | html %]</option>
                        [% END %]
                    [% END %]
                </select>
            </li>
            <li>
                <label for="search-type">[% t("Search type:") | html %]</label>
                <select id="search-type">
                    <option value="starts_with" selected>[% t("Starts with") | html %]</option>
                    <option value="contains">[% t("Contains") | html %]</option>
                </select>
            </li>
            <li>
                <label for="sidebar-category-filter">[% t("Category:") | html %]</label>
                <select id="sidebar-category-filter">
                    <option value="">[% t("Any") | html %]</option>
                    [% FOREACH c IN categories %]
                        <option value="[% c.categorycode | html %]">[% c.description | html %]</option>
                    [% END %]
                </select>
            </li>
            <li>
                <label for="sidebar-library-filter">[% t("Library:") | html %]</label>
                <select id="sidebar-library-filter">
                    <option value="">[% t("Any") | html %]</option>
                    [% FOREACH l IN libraries %]
                        <option value="[% l.branchcode | html %]">[% l.branchname | html %]</option>
                    [% END %]
                </select>
            </li>
        </ol>
    </fieldset>
    <fieldset class="action">
        <button type="submit" class="btn btn-primary">[% t("Search") | html %]</button>
        <button type="button" id="clear-search" class="btn btn-default">[% t("Clear") | html %]</button>
    </fieldset>
</form>
