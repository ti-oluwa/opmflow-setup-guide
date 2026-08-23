# Reporting a problem

If a script did not work the way this guide said it would, please tell us. This page walks through exactly how to do that, step by step, even if you have never opened an issue on GitHub before, and includes a template you can copy and fill in so that we have everything we need to help you quickly.

## Before you open an issue

A quick checklist that solves a surprising number of problems on its own:

1. Make sure you downloaded the latest version of the script, not an older copy saved somewhere from before. Scripts get fixed and improved over time.
2. Reread the specific step you got stuck on in the main [README.md](README.md). Most steps have a "What can go wrong here" section right underneath them, covering the most common issues.
3. Check the [FAQ.md](FAQ.md) in case someone has already run into the exact same thing.
4. If none of that helps, continue below.

## Step by step: how to open an issue on GitHub

If you have never done this before, here is exactly how.

1. Go to this repository's page in your web browser.
2. Look near the top of the page for a tab labeled **Issues**. Click it.
3. Click the green **New issue** button.
4. You will see a title field and a larger text box underneath it for the description.
5. For the title, write a short, specific summary, for example `Docker Desktop install fails with winget error on Windows 11`. Avoid vague titles like `it doesn't work`, since a specific title also helps future readers with the same problem find your issue.
6. In the larger text box, copy and paste the template from the [Issue template](#issue-template) section below, then fill in each part with your own details.
7. Scroll down and click the green **Submit new issue** button.

That's it. Someone will follow up on the issue itself, so keep an eye on it, either by revisiting the page or through any notification email GitHub sends you if you are logged in.

## Issue template

Copy everything inside the box below into the issue description box, then replace each placeholder with your own details. You do not need to remove the headings, just fill in the blanks underneath them. If a section does not apply to your situation, it is fine to write "not applicable" rather than deleting it.

````
### Which script were you running?

(For example: opmflow-setup.sh, opmflow-setup.ps1, resinsight-setup.sh, or resinsight-setup.ps1)


### Operating system and version

(For example: Windows 11 23H2, Ubuntu 24.04, macOS Sonoma 14.5 on Apple Silicon.
On Linux, running "cat /etc/os-release" in a terminal will show this.
On macOS, click the Apple logo, then "About This Mac."
On Windows, press the Windows key, type "winver", and press Enter.)


### Processor type

(Intel, AMD, Apple Silicon such as M1/M2/M3, or ARM. If unsure, say so.)


### Exact command you ran

(Copy and paste the exact command, including any options like --version or -Variant.
For example: sudo ./opmflow-setup.sh --variant amd64)


### What you expected to happen


### What actually happened


### Full error message or log output

(This is the single most useful thing you can include. Copy everything the terminal
printed, not just the last line, starting from a point before the error appeared.
Paste it between the two lines of three backticks below, so it displays as a
readable code block rather than a wall of plain text.)

```
PASTE YOUR FULL TERMINAL OUTPUT HERE
```

### Have you tried anything to fix it already?

(For example: re-running the script, restarting your computer, reinstalling Docker Desktop)


### Anything else that might be relevant

(For example: a work or restricted network, an unusual folder location, antivirus
software you know to be strict, a previous partial install of Docker or ResInsight)
````

## How to copy your terminal output

If you are not sure how to copy text out of a terminal window:

- **On Linux and macOS:** click and drag with your mouse to highlight the text, then use `Ctrl + Shift + C` (Linux) or `Cmd + C` (macOS) to copy it. Some terminals also let you right-click and choose Copy.
- **On Windows, in PowerShell:** click and drag to highlight the text, then press Enter, or right-click, to copy it. In newer Windows Terminal windows, `Ctrl + C` also works after highlighting text.

If the error scrolled off the top of the window and you cannot see the beginning of it anymore, you can usually scroll up inside the terminal window using your mouse wheel or a scrollbar, most terminals keep a decent amount of history.

## What happens after you submit an issue

Someone will read through what you submitted and reply on the same issue page, either asking a follow up question if something is unclear, or with a suggested fix. Please respond on that same issue thread rather than opening a new one for the same problem, it keeps the full conversation and context in one place, which makes it easier to help you and easier for others with the same issue to find the answer later.
