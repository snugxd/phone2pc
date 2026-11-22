# Phone2PC rules for the coding agent
Project: Flutter phone app that sends input to a Windows PC companion
(C#/.NET, in pc_companion/). Goal: a wireless touchpad with excellent
cursor responsiveness.

- Work in small steps. Do only the task requested; no extra features
  and no new packages unless asked.
- Before changing build config, check installed tools and report versions.
- Never fabricate binary files.
- If a command fails, stop, show the exact error, and explain the cause.
  Do not retry the same failing command more than once.
- Do not claim a build or test passed unless you ran it and saw it pass.
  If you cannot run something (e.g. the phone), say so and tell me
  exactly what to test.
- Do not modify working code outside the task.
- Keep networking off the UI thread; keep the input path lightweight.
- After each task, explain every file you changed in plain language.
- You may suggest better approaches or flag risks you notice, in a short "Suggestions" section at the end of your report. Do not implement a suggestion until I approve it.