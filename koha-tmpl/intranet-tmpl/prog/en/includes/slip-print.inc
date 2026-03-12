[% USE raw %]
<!-- slip-print.inc -->
<script nonce="[% Koha.CSPNonce | $raw %]">
    [% IF ( Koha.Preference('IntranetSlipPrinterJS') ) %]
        let autoprint = false;
        [% Koha.Preference('IntranetSlipPrinterJS') | $raw %]
    [% ELSE %]
        let autoprint = true;
        $( window ).load(function() {
            window.print();
            window.onafterprint = function () {
                window.close();
            }
            setTimeout('window.close()', 1000); //Hack from Chrome < 63
        });
    [% END %]
</script>
<!-- / slip-print.inc -->
