[% IF ( shibbolethAuthentication ) %]

    [% IF ( invalidShibLogin ) %]
    <!-- This is what is displayed if shibboleth login has failed to match a koha user -->
        <div class="alert alert-info">
            <p>
            Sorry, your Shibboleth identity does not match a valid library identity.
            [% IF ( casAuthentication ) %]
                [% IF ( invalidCasLogin ) %]
                <!-- This is what is displayed if cas login has failed -->
                    <p>Sorry, the CAS login also failed, if you have a local login you may use that below.</p>
                [% ELSE %]
                    If you have a CAS account, you may use that below.
                [% END %]
            [% ELSE %]
                If you have a local account, you may use that below.
            [% END %]
            </p>
        </div>
    [% ELSE %]
        <h4>Shibboleth Login</h4>
        <p>If you have a Shibboleth account,
         please <a href="[% shibbolethLoginUrl %]">click here to login</a>
    [% END %]

    [% IF ( casAuthentication ) %]
        <h4>CAS login</h4>
        <p>If you do not have a Shibboleth account, but you do have a CAS account,
    [% ELSE %]
        <h4>Local login</h4>
        <p>If you do not have a Shibboleth account, but you do have a local login, then you may login below:</p>
    [% END %]

[% END %]

[% IF ( casAuthentication ) %]
    [% IF ( shibbolethAuthentication ) %]
        [% IF ( casServerUrl ) %]
            please <a href="[% casServerUrl %]">click here to login</a>.<p>
        [% END %]
        [% IF ( casServersLoop ) %]
            please choose against which one you would like to authenticate: </p>
            <ul>
                [% FOREACH casServer IN casServersLoop %]
                    <li><a href="[% casServer.value %]">[% casServer.name %]</a></li>
                [% END %]
            </ul>
        [% END %]
    [% ELSE %]
        <h4>CAS login</h4>

           [% IF ( invalidCasLogin ) %]
               <!-- This is what is displayed if cas login has failed -->
               <p>Sorry, the CAS login failed.</p>
           [% END %]

           <p>If you have a CAS account,
           [% IF ( casServerUrl ) %]
               please <a href="[% casServerUrl %]">click here to login</a>.<p>
           [% END %]
 
           [% IF ( casServersLoop ) %]
               please choose against which one you would like to authenticate: </p>
               <ul>
                   [% FOREACH casServer IN casServersLoop %]
                       <li><a href="[% casServer.value %]">[% casServer.name %]</a></li>
                   [% END %]
                </ul>
           [% END %]
    [% END %]

    [% IF ( shibbolethAuthentication ) %]
        <p>Nothing</p>
    [% ELSE %]
        <h4>Local login</h4>
        <p>If you do not have a CAS account, but do have a local account, you can still log in: </p>
    [% END %]

[% END # / IF casAuthentication %]
