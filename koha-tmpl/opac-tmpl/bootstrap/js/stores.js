(function () {
    const permissions = (window.permissions = window.permissions || {});

    window.addPermissions = function (perms) {
        for (const key in perms) {
            if (Object.prototype.hasOwnProperty.call(perms, key)) {
                permissions[key] = perms[key];
            }
        }
    };
})();

(function () {
    const prefs = (window.prefs = window.prefs || {});

    window.addPrefs = function (sysprefs) {
        for (const key in sysprefs) {
            if (Object.prototype.hasOwnProperty.call(sysprefs, key)) {
                prefs[key] = sysprefs[key];
            }
        }
    };
})();
