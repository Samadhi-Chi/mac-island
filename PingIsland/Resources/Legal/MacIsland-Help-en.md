# Mac Island Help

## Getting started

First-run guidance covers presentation, connecting clients, and connection state. You can reopen it from the onboarding entry in Settings. Choose the docked presentation at the top of the screen or the movable floating presentation. Hover over Island or click to expand and see current sessions. If no sessions appear, open or start a task in a supported client, then check Mac Island's integration settings.

Enable only the integrations you need. Checking a connection does not install configuration. Installing, updating, rolling back, and uninstalling integrations require explicit actions. Installation backs up affected configuration. Avoid running copies from both Applications and a build directory at the same time.

## Current sessions and recent records

Current sessions shows sources currently observed. Titles use native client names; missing titles are labeled unavailable rather than replaced with project directories. Recent records contains routing information for previously observed sessions not currently displayed. It is not complete chat history.

Selecting a row selects the session. An explicit Open in client button requests navigation. Feedback distinguishes a located terminal, a sent opening request, app-only activation, and failure. macOS accepting an opening request does not confirm that the correct conversation is on screen.

Some command-line sessions offer a continuation preview and command copying. One-click CLI continuation is not certified in this version. Check the directory and session before copying; you decide whether to run the command.

## Content display and silence

The app stays silent. Activity can update the compact indicator without automatically opening details. Details open after hovering or clicking.

Content display offers three choices. Status only hides session titles, Bot names, content, and paths. Titles shows native titles, the client, and general status while hiding content, activity labels, paths, and session IDs. Details shows locally available details. New installs default to Titles; existing installs retain their previous detail preference.

Before meetings or screen sharing, choose Hide content temporarily to switch to Status only. Restore display returns to your previous choice. The temporary override lasts for this run only. It does not change the originating client or stop monitoring.

## Tasks needing attention

Island can indicate that a task needs attention, but it does not approve requests, answer questions, or send messages. Return to the originating client to complete those actions. The monitor demonstration opens a separate window showing running, needs-attention, and completed states, with docked and floating previews. It uses clearly labeled simulated data without querying real sessions or writing recent records.

## Muse, Grok Bot, and Dot

Muse and Grok Bot require separate opt-in and macOS Accessibility permission. They are experimental current-interface observations, limited to supported versions and layouts.

Each recognized current Bot context has one card. Activity entries do not become separate sessions. Muse 6.0 currently exposes the observed name only; native activities from Muse 4.1 can appear within the same Bot card. An unknown execution state does not count as running. This feature does not provide discovery of all background Bots, reliable task status, or chat restoration.

Source cards explain missing permission, a stopped app, an unsupported version, or an unreadable interface. Open app activates the application without guaranteeing a specific Bot is selected. Dot currently offers only an app-opening entry. Ordinary Codex sessions remain labeled Codex.

## If a session is missing

1. Confirm that only one Mac Island copy is running and the intended task is open in the client.
2. Check connection state and the last successful read in integration settings. A lack of new events alone does not mean a connection is broken.
3. If Codex is disconnected, use Reconnect. This reconnects Island's own observer without restarting Codex.
4. For hook-based sources, check the integration before explicitly installing or updating it. For Muse/Grok Bot, check source enablement, supported version, current interface, and system permission.
5. If the problem remains, record app and client versions and the source-card state. If needed, explicitly export diagnostics, then inspect the export before sharing it.

## Records and quitting

Settings lets you change recent-record retention or clear recent records. Clearing does not delete client history or clear every Island cache. See the offline privacy document for details.

Quitting Mac Island stops its observers without stopping tasks in other clients. Before deleting the app, you can uninstall installed Hooks from integration settings. System permissions can be revoked in macOS System Settings.

## Version and support

About shows the current version and provides offline privacy and third-party license documents. This version does not check for updates automatically. When About shows this product's website or support entry, you can use it. If none appears, consult the trusted channel from which you obtained the app for publisher contact information. Upstream Ping Island download and issue pages are not update or support routes for this product.
