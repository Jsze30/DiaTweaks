# Jason's fork

This fork makes two changes on top of upstream DiaTweaks: the **Enable ChatGPT** tweak (its code and setting key still say ChatGPT Sidebar), and a fix to the **Command Bar** tweak.

## Command Bar: new tabs

A new tab stays out of the sidebar while the command bar is open.
It only gets a sidebar row once you choose a result, and pressing Escape leaves no row behind.
The code is in `src/dylib/Patches/CommandBar/TabRows.m`.

## Enable ChatGPT: what it does

Dia's chat answers with ChatGPT instead of Dia's own AI, in the sidebar and in full window.
It uses your existing ChatGPT login from Codex, so there is no extra sign-in and no API key.
Dia's own header and composer stay as they are.
Only the message list is replaced with a native one that streams ChatGPT's replies.

- It looks like Dia's chat: Dia's sizes and spacing, a tip card on a new chat, and a Copy button under each finished reply.
- Your message bubbles take the space's color and follow it when the window switches spaces.
- The tabs attached in the composer's chips are read and sent with your message, once each, and the first one shows as a card above it.
- A favorite's chip keeps its saved URL, so when no page matches it exactly, the open page on the same site is read instead.
- Each tab has its own chat, which survives tab switches and Dia restarts.
- New chat starts the tab's chat over, and closing the tab clears it.
- ChatGPT can search the web live.
- ChatGPT can use your ChatGPT apps to read, but any action that would send or change something is declined.
- ChatGPT can list and read your open tabs, open new tabs, and search your browsing history.
- A question asked in Dia's command bar, such as on a new tab, is answered by ChatGPT in the window's chat beside that tab.
- Full window (View Options > Open in New Tab) shows the same chat: Dia moves its chat into a tab of its own, and the ChatGPT chat moves with it.

Turn on Enable ChatGPT in Dia Settings, under the AI section.
Turning it off gives Dia's own AI back in both places.
It needs the Codex app or CLI installed and signed in with ChatGPT.

## How it works

Dia's chat, in the sidebar or in a tab of its own, is mostly native AppKit.
Its message list is a web page, and its replies come from Dia's servers, encrypted both ways.
So swapping the AI under Dia's own message list isn't possible.
Instead, the tweak:

- Hides Dia's web message list and puts a native transcript view in its place, under Dia's composer.
- Clears Dia's onboarding card and suggested prompts, so only the ChatGPT chat shows.
- Catches Return and the Send button in Dia's composer, takes the text, and clears the field.
- Sends the text to a local `codex app-server` process, which talks to ChatGPT with your Codex login.
- Streams the reply into the transcript, rendered from Markdown.
- Keeps one chat per tab, saved as a Codex thread so it comes back after Dia restarts.
- Finds Dia's chat by its prompt queue, which both the sidebar and the full-window tab have, and follows Dia's chat ID when Dia moves the chat to a tab.
- Stops a reply on Escape.

Codex runs with live web search, ChatGPT apps, and the tab and history tools, which Dia answers.
Each app call asks first: read-only calls run, and anything that sends or changes something is declined.
Shell, MCP servers, browser and computer use, and Codex history stay off, and the sandbox is read-only.
Page text is marked as untrusted, so the model treats it as material, not instructions.

## Files

Everything lives in `src/dylib/Patches/ChatGPTSidebar/`:

- `ChatGPTSidebar.m`: the tweak's settings entry and its self-check.
- `Host.m`, `Input.m`, `Hints.m`: attach to Dia's sidebar, catch sends from its composer, and clear Dia's hints.
- `Service.m`, `Client.m`, `Protocol.m`, `Runtime.m`: start and talk to `codex app-server`.
- `Conversation.m`, `Events.m`, `Tabs.m`, `Restore.m`: one chat per tab, the streamed reply events, and bringing a saved chat back.
- `Transcript.m`, `Rows.m`, `Scroll.m`, `Empty.m`: the native message list.
- `Card.m`, `Copy.m`, `Tip.m`, `Accent.m`, `Hover.m`, `Icons.m`: the shared page's card, the Copy button, the new-chat tips, the space's bubble color, and the hover buttons and Phosphor icons they use.
- `Markdown.m`, `Inline.m`: Markdown rendering.
- `Page.m`, `Attachments.swift`: find the tabs attached in the composer and read their text.
- `Tools.m`: the tab and history tools, and the read-only check on app calls.
- `Ask.m`: takes a question from Dia's command bar and hands it to ChatGPT.
- `Motion.m`: the chat's fades and rises.
- `Settings.m`: Sign Out and Choose Codex buttons.

## Status

It builds and `make check` passes.
Tested inside Dia: ChatGPT replies in the sidebar, the new look, the page card from the composer's chips, and the command bar keeping a new tab out of the sidebar.
Per-tab chats, New chat, restarts and favorites were checked inside Dia as each fix was built, but not re-tested together after merging.
The command bar question hand-off is new and has only been lightly tested.
Full window was tested inside Dia: the chat moves from the sidebar to its own tab with its messages, at Dia's own column width.
