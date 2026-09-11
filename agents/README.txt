Agent roster
============

Edit agents.json and add one object per agent under the "agents" array:

{
  "name": "Readable name",
  "description": "Optional short description",
  "icon": "/absolute/path/to/official-agent-icon.png",
  "command": "the command to execute",
  "terminal": true
}

Set `icon` to an official local image path or an `http://`/`https://` image URL.
If omitted or unavailable, the selector displays the first letter of the agent
name as a fallback. Commands launch inside Kitty by default, which is appropriate for CLI agents
such as Hermes and Codex. The command is passed to `sh -lc`, so shell syntax,
arguments, pipes, and working-directory changes are supported. Quote paths and
arguments as needed. Set `"terminal": false` for a GUI command that should be
started without a terminal window.
After selecting an agent, the command is detached and the selector window exits.
Press Escape or click the close button to dismiss the selector without launching.

The selector is opened with Super+A.
