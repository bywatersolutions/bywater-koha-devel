[% BLOCK translate_justification_types %]
    [%  SWITCH type %]
        [%   CASE 'L' %]left
        [%   CASE 'C' %]center
        [%   CASE 'R' %]right
    [%  END %]
[% END %]

[% BLOCK translate_unit_types %]
    [% SWITCH type %]
        [%   CASE 'POINT' %]pt
        [%   CASE 'INCH' %]in
        [%   CASE 'MM' %]mm
        [%   CASE 'CM' %]cm
    [% END %]
[% END %]
