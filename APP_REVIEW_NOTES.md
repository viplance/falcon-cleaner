Falcon Cleaner 1.2.4 (8) — review notes

This build addresses the cleanup failure reported for submission
2da39642-6a36-4ef6-86d4-fce6b2ac5d59 (Guideline 2.1(a)).

To test application removal:

1. Install a disposable, user-owned application in /Applications and quit it.
2. Open Falcon Cleaner, select that application and click Clean Up, then Move to Trash.
3. In the macOS access dialog, select the Applications folder and click Allow Access.
4. Verify that the application's bundle has moved to the Trash. It can be restored from there.

To include related app data, click Include App Data… before cleaning, select your user
Library folder in the access dialog, and wait for the rescan. Without that optional
permission, cleanup includes application bundles only. Folder access lasts for the
current session and is requested again after quitting and reopening Falcon Cleaner.

The App Store build uses the App Sandbox and native FileManager Trash operations.
It does not use Finder automation or request administrator privileges for cleanup.
Running applications must be quit first. Files that require elevated privileges cannot
be removed; the app shows an error that remains until dismissed. Canceling access leaves
the current application's files unchanged. Any earlier items in a batch that were
already moved remain in the Trash.

Homebrew, startup services and process management are not offered in this sandboxed build.
