# Contributing

Thank you for wanting to help improve these scripts or their documentation. This page explains how, at a level that does not assume you have contributed to an open source project before.

## Ways to contribute, even without writing any code

- **Report a problem.** See [ISSUE.md](ISSUE.md). Reporting a clear, detailed issue is genuinely one of the most useful things you can do, even if you never touch the scripts yourself.
- **Suggest a documentation fix.** If something in the [README.md](README.md) or [FAQ.md](FAQ.md) was unclear, confusing, or just plain wrong, telling us is valuable on its own, even if you do not want to write the fix yourself. Open an issue describing what confused you and why.
- **Improve the documentation yourself.** If you are comfortable editing a text file, you can propose the fix directly, see the step by step guide below.
- **Improve or fix a script.** The same process below applies to changes to `opmflow-setup.sh`, `opmflow-setup.ps1`, `resinsight-setup.sh`, or `resinsight-setup.ps1`.

## Step by step: proposing a change

This uses a process called a pull request, a way of proposing a specific change to a file and having it reviewed before it becomes part of the repository. Here is how, from scratch.

1. **Make a copy of the repository under your own account.** On the repository's page, click the **Fork** button near the top right. This creates your own personal copy that you are free to change however you like, without affecting the original.
2. **Get a local copy of your fork on your computer.**

   ```
   git clone https://github.com/YOUR_USERNAME/YOUR_FORKED_REPO.git
   cd YOUR_FORKED_REPO
   ```

   If you do not have `git` installed, see [Git's official download page](https://git-scm.com/downloads) for instructions for your operating system.

3. **Create a new branch for your change.** A branch is a separate line of work, so your change is kept apart from the main version until it is reviewed.

   ```
   git checkout -b fix-typo-in-readme
   ```

   Use a short, descriptive name for your branch, related to what you are actually changing.

4. **Make your change** using any text editor. If you are editing a `.md` file, plain text editors like Notepad, TextEdit, VS Code, or any code editor all work fine. If you are editing one of the `.sh` or `.ps1` scripts, see the guidelines below first.

5. **Save your change, then record it with git:**

   ```
   git add .
   git commit -m "Fix typo in README installation steps"
   ```

   Write a commit message that describes what you changed and, ideally, why.

6. **Send your change back up to your fork on GitHub:**

   ```
   git push origin fix-typo-in-readme
   ```

7. **Open a pull request.** Go back to your fork's page on GitHub. You should see a prompt suggesting you open a pull request from the branch you just pushed. Click it, fill in a short description of what you changed and why, and submit it.

8. Someone will review your change, possibly asking questions or requesting small adjustments directly on the pull request page. Once it looks good, it will be merged into the main repository, and your contribution becomes part of it.

## Guidelines for changing the scripts

These scripts are meant to be safe and predictable to run on someone else's computer, often with administrator rights, so changes to them are held to a higher standard than a typical documentation fix.

- **Explain unusual decisions with a comment.** If you write something that looks odd at first glance, for example working around a strange platform-specific quirk, leave a comment explaining why, so the next person (including a future you) does not "simplify" it back into the original bug.
- **Do not silently expand what the script does.** If your change makes the script install something new, touch a new part of the filesystem, or need a new kind of permission, call that out clearly in your pull request description so it can be reviewed carefully.
- **Test on the actual platform you are changing, if you can.** A fix for the Windows script should be tested on Windows, a fix for Linux permission handling should be tested on Linux, since this class of bug often does not show up any other way.
- **Keep error messages clear and specific.** Part of what makes these scripts usable by people new to the command line is those "What can go wrong here" style error messages. If you add a new failure case, add a clear message explaining what happened and, if possible, how to fix it, rather than letting a raw system error surface on its own.
- **Match the existing style.** Look at how the surrounding code is written (variable naming, comment style, how errors are reported) and follow the same pattern rather than introducing a new one.

## Guidelines for changing the documentation

- Keep the tutorial, step by step tone used throughout the README. This documentation is written for people who may not be comfortable with the command line yet, especially on Windows, so please keep new sections approachable rather than assuming prior knowledge.
- If you introduce a new technical term, add it to the [Glossary](README.md#glossary-words-used-in-this-guide) section, in plain, simple language, the same way the existing entries are written.
- If you add a new step to a walkthrough, consider whether it needs its own "What can go wrong here" note underneath it, the same way the existing steps do.
- Avoid using em dashes or en dashes in this documentation. Use regular hyphens, commas, or separate sentences instead.

## Questions before you start

If you are not sure whether a change would be welcome, or you want feedback on an idea before spending time building it, open an issue describing your idea first (see [ISSUE.md](ISSUE.md) for the general process of opening an issue, even though that page is written for bug reports specifically, the same steps apply). This can save you from doing work that might not fit the direction of the project.
