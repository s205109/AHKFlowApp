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

    // Copied from Startup/StartupError.razor so both failure screens look the same. They stay
    // inline because Blazor never started, so MudBlazor's theme provider is not mounted.
    var containerStyle =
        'min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1.5rem;' +
        'font-family:Inter,Roboto,sans-serif;background:#eef3ec;';

    var cardStyle =
        'max-width:560px;width:100%;background:#fff;border-radius:12px;padding:2.5rem 2rem;' +
        'box-shadow:0 10px 30px rgba(0,0,0,.08);text-align:center;';

    var buttonStyle =
        'background:#6AA84F;color:#fff;border:none;border-radius:8px;padding:.6rem 1.5rem;' +
        'font-size:1rem;font-weight:500;cursor:pointer;';

    function showBootError() {
        var app = document.getElementById('app');
        if (!app) {
            return;
        }

        var container = document.createElement('div');
        container.setAttribute('role', 'alert');
        container.setAttribute('tabindex', '-1');
        container.setAttribute('data-test', 'boot-error');
        container.setAttribute('style', containerStyle);
        container.innerHTML =
            '<div style="' + cardStyle + '">' +
                '<div style="font-size:2.5rem;line-height:1;margin-bottom:1rem;">⚠️</div>' +
                '<h1 style="margin:0 0 .5rem;font-size:1.5rem;color:#1f2933;">Couldn\'t load the app</h1>' +
                '<p style="margin:0 0 1.25rem;color:#52606d;">' +
                    'The app started to load, but some of its files could not be downloaded.' +
                '</p>' +
                '<div style="text-align:left;background:#f5faf3;border:1px solid #d9e6d4;' +
                    'border-radius:8px;padding:1rem 1.25rem;color:#3e4c59;">' +
                    '<strong style="display:block;margin-bottom:.5rem;color:#1f2933;">How to fix it</strong>' +
                    '<ul style="margin:0;padding-left:1.2rem;">' +
                        '<li style="margin-bottom:.5rem;">Reload the page. This fixes most cases.</li>' +
                        '<li>If reloading does not help, check your internet connection and ' +
                            'try again in a few minutes.</li>' +
                    '</ul>' +
                '</div>' +
                '<div style="margin-top:1.5rem;">' +
                    '<button type="button" data-test="boot-error-reload" style="' + buttonStyle + '">' +
                        'Reload' +
                    '</button>' +
                '</div>' +
            '</div>';

        // Replaces the loading circle, which is frozen and no longer means anything.
        app.replaceChildren(container);

        container.querySelector('[data-test="boot-error-reload"]')
            .addEventListener('click', function () {
                window.location.reload();
            });

        // The message appears after the page has loaded, so a screen reader will not announce it
        // on its own. Focus was left on a loading circle that no longer exists.
        container.focus();
    }

    // The .NET runtime reports a failed asset download as an uncaught error, and the promise
    // returned by Blazor.start() then never settles, so that uncaught error is the only signal we
    // get. Only the runtime's own two failure messages count. Reacting to any uncaught error would
    // be far too wide: a slow boot that still succeeds must not be reported as a failure just
    // because an unrelated script threw while it was loading.

    // Thrown by the runtime for each boot file it could not download, as:
    // "download '<url>' for <name> failed <status> <inner error>".
    var downloadFailurePattern = /download '.*' for .* failed/;

    // Thrown by blazor.webassembly.js when the boot itself gives up, as:
    // "Failed to start platform. Reason: <inner error>". The runtime does not always get this far,
    // so it confirms a failure but cannot be relied on to report one.
    var startFailurePattern = /Failed to start platform/;

    // The runtime retries a failed download, so one failed download does not mean the boot is lost.
    // Wait, then report only if the boot still has not finished.
    var bootFailureGraceMs = 10000;

    var bootSettled = false;

    function messageOf(error) {
        if (!error) {
            return '';
        }

        var message = typeof error === 'string' ? error : error.message;
        return typeof message === 'string' ? message : '';
    }

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
            return;
        }

        showBootError();
    }

    function onUncaughtDuringBoot(error) {
        if (bootSettled) {
            return;
        }

        var message = messageOf(error);

        // The boot gave up, so there is nothing left to wait for.
        if (startFailurePattern.test(message)) {
            onBootFailed(error);
            return;
        }

        if (downloadFailurePattern.test(message)) {
            window.setTimeout(function () {
                onBootFailed(error);
            }, bootFailureGraceMs);
        }
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
