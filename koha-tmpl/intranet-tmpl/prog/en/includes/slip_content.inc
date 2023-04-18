<style>
    #slip, #receipt {
        text-align:[% PROCESS translate_justification_types type=notice.text_justify | trim %];
        font-size:[% notice.font_size %]px;
        width:[% notice.notice_width %][% PROCESS translate_unit_types type=notice.units | trim %];
        margin-top:[% notice.top_margin %][% PROCESS translate_unit_types type=notice.units | trim %];
        margin-left:[% notice.left_margin %][% PROCESS translate_unit_types type=notice.units | trim %];
    }

    h3, h4, th, td, th:last-child, td:last-child {
        text-align:[% PROCESS translate_justification_types type=notice.text_justify | trim %];
        font-size:[% notice.font_size %]px;
    }
</style>

[% IF notice.is_html %]
    [% notice.content | $raw %]
[% ELSE %]
<pre>
    [% notice.content | html %]
</pre>
[% END %]
