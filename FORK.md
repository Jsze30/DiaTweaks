# Jason's fork

This fork adds one tweak on top of upstream DiaTweaks: **ChatGPT Sidebar**.

## What it does

Dia's chat sidebar answers with ChatGPT instead of Dia's own AI.
It uses your existing ChatGPT login from Codex, so there is no extra sign-in and no API key.
Dia's own header and composer stay exactly as they are, so the sidebar keeps your profile's colors.
Only the message list is replaced with a native one that streams ChatGPT's replies.
The page you're on is sent along with your message, once per page.

Turn it on in Dia Settings, under the AI section.
It needs the Codex app or CLI installed and signed in with ChatGPT.

## How it works

Dia's chat sidebar is mostly native AppKit.
Its message list is a web page, and its replies come from Dia's servers, encrypted both ways.
So swapping the AI under Dia's own message list isn't possible.
Instead, the tweak:

- Hides Dia's web message list and puts a native transcript view in its place, under Dia's composer.
- Catches Return and the Send button in Dia's composer, takes the text, and clears the field.
- Sends the text to a local `codex app-server` process, which talks to ChatGPT with your Codex login.
- Streams the reply into the transcript, rendered from Markdown.
- Resets the chat when you press Dia's New chat button, and stops a reply on Escape.

Codex runs with tools, shell, web search, MCP servers and history all turned off, so it can only chat.
Page text is marked as untrusted, so the model treats it as material, not instructions.

## Files

Everything lives in `src/dylib/Patches/ChatGPTSidebar/`:

- `ChatGPTSidebar.m`: the tweak's settings entry and its self-check.
- `Host.m`, `Input.m`: attach to Dia's sidebar and catch sends from its composer.
- `Service.m`, `Client.m`, `Protocol.m`, `Runtime.m`: start and talk to `codex app-server`.
- `Conversation.m`, `Events.m`: one chat per window, and the streamed reply events.
- `Transcript.m`, `Rows.m`, `Scroll.m`, `Empty.m`: the native message list.
- `Card.m`, `Copy.m`, `Tip.m`, `Accent.m`, `Hover.m`, `Icons.m`: the shared page's card, the Copy button, the new-chat tips, the space's bubble color, and the hover buttons and Phosphor icons they use.
- `Markdown.m`, `Inline.m`: Markdown rendering.
- `Page.m`: reads the current page's text.
- `Settings.m`: Sign Out and Choose Codex buttons.

## Status

It builds and `make check` passes.
A real ChatGPT reply through the same Codex setup was tested outside Dia and came back in about 3 seconds.
It hasn't been fully tested inside Dia yet.
