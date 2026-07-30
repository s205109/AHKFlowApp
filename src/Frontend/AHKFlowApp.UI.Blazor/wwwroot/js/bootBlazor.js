// Blazor is started manually so a boot failure can be handled. With autostart on, a failed
// asset download becomes an uncaught promise rejection, the boot UI has no failure branch,
// and the loading circle sits at 99% forever.
(function () {
    'use strict';

    var reloadGuardKey = 'ahkflowapp-boot-retry-reload';

    // A fresh page load fixes most boot failures, so the first failure reloads once and the
    // guard makes sure it happens at most once per tab session. Mirrors the guard in
    // registerServiceWorker.js. Returns false when sessionStorage is unavailable, so a browser
    // with storage blocked reports the failure instead of throwing inside the error handler.
    function tryClaimReload() {
        try {
            if (window.sessionStorage.getItem(reloadGuardKey) === 'true') {
                return false;
            }

            window.sessionStorage.setItem(reloadGuardKey, 'true');
            return true;
        } catch (storageError) {
            console.error('Boot retry guard unavailable:', storageError);
            return false;
        }
    }

    function clearReloadGuard() {
        try {
            window.sessionStorage.removeItem(reloadGuardKey);
        } catch (storageError) {
            console.error('Boot retry guard unavailable:', storageError);
        }
    }

    // How long to wait after an uncaught error before calling the boot failed. A failed asset
    // download is reported by the .NET runtime as an uncaught error, and the promise returned by
    // Blazor.start() then never settles, so the uncaught error is the only signal we get. Waiting
    // a few seconds first means an unrelated error thrown by a boot that still succeeds is ignored.
    var bootFailureGraceMs = 5000;

    var bootSettled = false;

    function onBootSucceeded() {
        bootSettled = true;
        clearReloadGuard();
    }

    function onBootFailed(error) {
        if (bootSettled) {
            return;
        }

        bootSettled = true;

        // Required, not optional: catching the rejection removes the browser's own
        // "Uncaught (in promise)" log, so without this a developer is left with less
        // than before. Pass the original error object, never a summarized string.
        console.error('Blazor failed to start:', error);

        if (tryClaimReload()) {
            window.location.reload();
        }
    }

    function onUncaughtDuringBoot(error) {
        if (bootSettled) {
            return;
        }

        window.setTimeout(function () {
            onBootFailed(error);
        }, bootFailureGraceMs);
    }

    window.addEventListener('error', function (event) {
        onUncaughtDuringBoot(event.error || event.message);
    });

    window.addEventListener('unhandledrejection', function (event) {
        onUncaughtDuringBoot(event.reason);
    });

    Blazor.start()
        .then(onBootSucceeded)
        .catch(onBootFailed);
})();
