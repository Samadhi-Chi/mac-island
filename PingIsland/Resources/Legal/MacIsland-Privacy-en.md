# Mac Island Privacy

Updated October 31, 2026. Applies to this version of Mac Island.

## Observation on your Mac

Mac Island displays supported coding assistants' session state on your Mac and, when you act, requests that the relevant client or window open. It does not approve or deny requests, answer questions, send messages, or run agent tasks for you. One-click CLI continuation is not enabled in this version.

This version does not enable telemetry, advertising tracking, automatic update checks, or remote SSH services. It does not upload sessions or usage records to the developer. Observation communicates with local clients and the local Bridge. External links open in your browser or the relevant app; third-party clients' own network activity is governed by their privacy policies.

Cursor account-token reading and direct network quota requests are disabled in
this monitor-only product. Codex observation uses a private pipe to an observer
process owned by Island; stopping it does not terminate your Codex application.

## Information read

Depending on the integrations you enable and use, the app may read local session state, native titles, project directories, client and terminal identifiers, quota information, recent progress, and conversation or tool content. It uses this information to display local activity and return to the originating client. Conversation content and native session titles are displayed in memory and are not written to recent records. Mac Island is not a complete chat archive or backup.

Screen-content masking controls the Island display only; it does not mask the originating client or other apps. A status-only display does not stop underlying monitoring. Quitting Mac Island stops its observers without stopping tasks in your other clients.

## Information stored locally

- Preferences: presentation mode, shortcuts, content-display choices, integration settings, and experimental-source enabled/paused state.
- Recent records: client, origin, native session ID, project directory, and activity time. The default is seven days and at most 200 records. Settings also offer 24 hours/100 records, this run only, or no recording.
- Association and quota caches: client-routing information, session identifiers, project directories, and locally obtained quota summaries used for association and display across launches. These caches are separate from recent records and are not governed by the seven-day recent-record limit.
- Local diagnostics: app version, runtime environment, integration and connection state, and other troubleshooting information. This version stops adding legacy navigation debug logs without automatically deleting historical files. The operating system may also retain crash reports or runtime logs.

Legacy per-session token analytics are disabled. Bridge debug logging is off by
default; if explicitly enabled for troubleshooting, it records only fixed event
categories, timestamps and byte counts, never raw input, paths or native IDs.
On the next Bridge invocation, disabling logging removes recognized owned Bridge logs; enabled logging applies its retention limit. Unrecognized files and legacy analytics are not automatically removed.
Bridge debug files may remain under `~/.mac-island-debug`; old usage analytics
may remain in the MacIsland Application Support directory.

The recent-record file is `MacIsland/recent-sessions-v1.json` inside your local Application Support directory; `session-associations.json` in the same directory stores associations. Quota caches use `~/.mac-island/cache`. Navigation diagnostics may use `~/.ping-island-debug`. These locations are not automatically uploaded.

## Retention and clearing

Clear recent records clears only the Island recent index. It does not delete client chat history, association caches, diagnostics, or integration configuration. A cutoff prevents unchanged old records from immediately returning. Selecting this run only or no recording removes the persistent recent index.

Use the uninstall action in integration settings to remove integrations; deleting the app alone does not revoke installed Hooks. Uninstall handles configuration managed by Island; retain existing backups as needed. After quitting the app, you can manage the Island cache and diagnostic files listed above in Finder. Needed caches may be created again when observation resumes. Do not delete a client's own configuration or chat directories to clear Island data.

## Permissions and experimental sources

Explicit integration installation changes the relevant client's local configuration and creates backups. Integrations are not installed automatically on first launch. Some window-navigation features require macOS Automation or Accessibility permission. You can manage or revoke permission in System Settings.

Muse and Grok Bot are experimental interface observations, disabled by default. Only after you enable a source and grant Accessibility access does the app read supported current-interface metadata. It skips conversation bodies and input subtrees and does not automatically click, scroll, or switch the source app. Native Activity labels may include short result descriptions from the source. Observations and Bot names remain in memory and do not enter recent records or telemetry. A supported interface does not provide discovery of every background Bot or confirm that a task is running. Unsupported versions and unreadable interfaces show a reason. Dot currently has an app-opening entry, without an independent task-observation source.

## Diagnostics and support

Diagnostic export is initiated by you and saved locally, without automatically sending the file to anyone. The export contains only a health summary and an explanatory file: app and macOS versions, fixed Codex connection-state/failure categories, and Muse/Grok Bot enablement, fixed source-state categories, and numeric versions. It does not copy client configuration, logs, indexes, project paths, session titles, conversations, or credentials. The historical upstream diagnostic collector is not used for this product's export. Inspect the file before sharing and share only what is needed for the problem. Do not additionally attach login passwords, API keys, full conversations, or private keys.

This document is available offline in the app. When About shows this product's website or support entry, you can use that entry. If none appears, consult the trusted channel from which you obtained the app for publisher contact information. The upstream Ping Island issue tracker is not Mac Island support. Public distribution should also provide publicly accessible, current privacy information.

## Third parties and changes

Apple, your coding assistants, and other external services have their own privacy policies. Third-party licenses are available offline in the app. If update checks, paid services, or other data handling are introduced, this notice and any necessary user choices will be updated. This notice does not mean those features are currently enabled.
