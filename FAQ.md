# Frequently asked questions

This page collects common questions about the OPM Flow and ResInsight installer scripts. If your question is not answered here, check the main [README.md](README.md) first, then see [ISSUE.md](ISSUE.md) for how to ask us directly.

## General

### Do I need to know how to code to use these scripts?

No. You need to be comfortable typing a few commands into a terminal window and pressing Enter, and copying a file from one folder to another. The main [README.md](README.md) walks through every step, including what a terminal is and how to open one, so it is fine if you have never used one before.

### Do I need to clone this repository with git?

No. You only need the one script file for your platform and the tool you want. See [Getting the scripts onto your computer](README.md#getting-the-scripts-onto-your-computer) in the README for a few different ways to download just that one file.

### Is it safe to run these scripts?

We have reviewed them and, as far as we can tell, they do not contain anything malicious. That said, we cannot make an absolute guarantee about any script from any source, including ours. Please read the [security disclaimer](README.md#security-disclaimer-please-read-this-first) in the README before running anything with administrator rights. If you are able to read through the script yourself before running it, that is always a good habit.

### Why do these scripts need administrator access (sudo or elevated PowerShell)?

Installing software system-wide, and adding new commands to a shared location that any user on your computer can run, both require administrator permission on every operating system. On Linux and macOS this shows up as `sudo`. On Windows it shows up as an elevated PowerShell prompt, and only for the specific step of installing Docker Desktop itself, not for the rest of the OPM Flow script, and not at all for the ResInsight script by default.

### Can I install without giving administrator access at all?

For ResInsight, yes. Use the `--install-root` option (Linux and macOS) to install into a folder you already own, for example your home folder. See the [ResInsight on Linux and macOS](README.md#resinsight-on-linux-and-macos) section of the README.

For OPM Flow, the answer is a little more mixed. On Windows, the script itself does not need administrator rights, only the one-time Docker Desktop installation does, and only if Docker was not already installed. On Linux and macOS, the OPM Flow script installs itself system-wide by design, so that the `flow` command is available to any user on the machine, which does need `sudo`.

### What is the difference between OPM Flow and ResInsight? Do I need both?

OPM Flow runs reservoir simulations. It takes a `.DATA` file describing your reservoir and calculates how it behaves over time. It has no graphical interface, you run it from a terminal.

ResInsight is a 3D viewer for looking at the results afterward. It has a full graphical interface with windows and menus.

You only need OPM Flow if you want to run simulations. You only need ResInsight if you want to visualize results (whether from OPM Flow or another compatible simulator). Many people use both together: OPM Flow to run the simulation, ResInsight to look at what came out of it.

## Docker and OPM Flow

### What actually is Docker, in simple terms?

Think of Docker as a way of running a program inside its own sealed, self-contained box, called a container, that already has everything that program needs bundled inside it. Instead of you having to install OPM Flow's specific dependencies and library versions by hand, which can be a fiddly and error-prone process, you download a ready-made box that already has all of that set up correctly, and just run it. See the [Glossary](README.md#glossary-words-used-in-this-guide) in the README for more terms like this.

### Do I need to understand Docker to use OPM Flow through this script?

No. The script and the `flow` command it installs handle all of the Docker details for you. You only need to know that Docker needs to be installed and running in the background, which the script checks and handles automatically.

### The script says it is installing Docker, but I thought I already had it. What happened?

The script checks for Docker using the `docker` command. If that command is not found on your system, it assumes Docker is not installed and tries to install it. If you do have Docker installed but it is somehow not on your PATH (rare, but possible with certain custom installations), you may see it try to reinstall. This should not cause any harm, but if you would rather avoid it, make sure `docker --version` works correctly in a fresh terminal window before running the setup script.

### Why does OPM Flow on Windows need WSL2? I just want to run a simulator, not learn Linux

Docker containers are built on Linux under the hood, even the ones you run from Windows or macOS. On Windows specifically, Docker Desktop needs a real Linux environment to actually run those containers in, and WSL2 is what provides that. You do not need to learn or use Linux directly yourself, WSL2 mostly works invisibly in the background once it is set up. The [OPM Flow on Windows](README.md#opm-flow-on-windows) section of the README walks through installing it.

### How do I know if Docker is actually running right now?

On Linux, run `sudo systemctl status docker` in a terminal. On Windows and macOS, look for the Docker whale icon in your system tray (Windows, near the clock) or menu bar (macOS). If it is not animating or shows an error, Docker Desktop is not fully running yet.

### Can I run OPM Flow on a different processor architecture, like Apple Silicon or an ARM-based server?

Yes. The script automatically detects your processor type and downloads the matching image variant. You generally do not need to do anything special. If you want to force a specific variant anyway, both scripts accept a variant option, `--variant` on Linux and macOS, `-Variant` on Windows. See the OPM Flow sections of the README for the full list of supported variants.

### How do I switch to a different OPM Flow version later?

On Linux and macOS: `sudo opmflow upgrade` for the latest version, or `sudo opmflow upgrade 2026.04` for a specific one. On Windows, the same commands work without `sudo`, since configuration is stored per-user there. See [Using OPM Flow after install](README.md#using-opm-flow-after-install) in the README.

### Where does OPM Flow read and write my files?

Wherever you are standing in your terminal (your current folder) when you run the `flow` command. The script automatically shares that folder with the Docker container, so OPM Flow can read your `.DATA` file and write its output right there, without you needing to configure anything.

## ResInsight

### Why does the installer sometimes say a version has no build for my platform?

ResInsight has not always supported every platform on every release. Windows support has existed the longest, macOS was added more recently, and Linux builds (both RHEL-based and Ubuntu-based) are newer still. Rather than guessing or assuming a file exists, the installer checks GitHub directly for what that specific release actually published, and tells you plainly if there is nothing for your platform in that particular version. Trying a newer version, or `latest`, usually resolves this.

### What is the difference between the gcc and clang Ubuntu builds, and which one should I pick?

These refer to two different compilers, programs used to build ResInsight from its source code, that were both used to produce a version of ResInsight for Ubuntu. Unless you have a specific technical reason to prefer one, the default (`gcc`) is a safe, common choice. This option only appears on Ubuntu and Debian-based systems, and is ignored everywhere else.

### The installer finished, but running `resinsight` says permission denied. What do I do?

This was a bug in earlier versions of the installer related to file permissions when running under `sudo`. It has since been fixed. Re-running the installer (it is safe to run more than once) will recreate the command with the correct permissions. If you are still on an old copy of the script, download the latest version first.

### On macOS, I get a message that ResInsight "is damaged and can't be opened." What is going on?

ResInsight's current macOS build is not digitally signed by Apple, and macOS's Gatekeeper security feature is extra cautious about unsigned applications downloaded from the internet. The installer already removes the specific flag that triggers this warning as part of installing it. If you still see the message, the most likely explanation is that the app was moved or re-downloaded some other way after the installer ran. Re-running the installer should resolve it.

### Does reinstalling redownload everything from scratch every time?

No. Both scripts check whether the exact version you are asking for is already installed and working, and skip straight to "nothing to do" if so. Even if you force a reinstall, or point the installer at a different install location, previously downloaded files are kept in a small cache and reused rather than downloaded again, as long as the file matches what GitHub expects (checked by file size).

### Can I install ResInsight without it showing up in my applications menu or Start Menu?

Yes. On Linux, pass `--no-desktop-entry`. On Windows, pass `-NoShortcut`. On macOS, ResInsight always appears in Launchpad automatically once installed, since that is simply how any application placed in the Applications folder behaves on macOS, there is no separate step to opt out of.

## Uninstalling

### How do I uninstall OPM Flow or ResInsight?

Each tool has a matching uninstall script: `opmflow-uninstall.sh` and `opmflow-uninstall.ps1` for OPM Flow, `resinsight-uninstall.sh` and `resinsight-uninstall.ps1` for ResInsight. The full walkthrough, with a step by step guide for every platform, is in [Part 3: Uninstalling](README.md#part-3-uninstalling) of the README. If you only want the short version: download the script for your system, run it once with `--dry-run` (or `-DryRun` on Windows) to preview what it will remove, then run it for real.

### Will uninstalling delete my simulation files or my ResInsight projects?

No. The uninstallers only remove what the installers put on your computer. Your `.DATA` files, simulation results and ResInsight project files are in your own folders and are never touched. ResInsight's own saved preferences (such as its list of recent files) are not touched either.

### Does the uninstaller remove Docker?

No, on purpose. Docker is a general purpose tool that many people use for other things, and the OPM Flow installer does not keep a record of whether it was the one that installed Docker, so the uninstaller cannot know whether removing it would break something else. It removes the OPM Flow Docker images that were downloaded, but leaves Docker itself and WSL2 alone. If you want to remove those too, see [Removing Docker and WSL2 yourself](README.md#removing-docker-and-wsl2-yourself-optional), and read the warning there first, because removing Docker Desktop also removes every other image, container and volume stored in it.

### How do I see what an uninstall script would do without it actually doing anything?

Run it with `--dry-run` (Linux and macOS) or `-DryRun` (Windows). It lists exactly what it found and what it would remove, then stops without changing anything. A dry run on Linux and macOS does not even need `sudo`.

### I want to free up disk space but keep OPM Flow. What can I do?

The Docker images are the biggest part of an OPM Flow installation. Every time you switch versions with `opmflow upgrade`, the new image is downloaded and the old one is left behind. You can see the ones you have with `docker image ls openporousmedia/opmreleases`, and remove an old one you no longer use with `docker rmi` followed by its name and tag as shown in that list. Docker will refuse to remove one that is currently in use, which is what you want. Do not remove the one that you are currently using, or OPM Flow will simply download it again the next time you run it.

### I have two versions of ResInsight installed. Can I remove only one?

Yes. Use `--version` on Linux and macOS, or `-Version` on Windows, for example `./resinsight-uninstall.sh --version 2026.06.0`. Only that version is removed, and a command, shortcut or menu entry that points at the version you are keeping is left alone and keeps working.

### The uninstaller said it left something in place. Is that a problem?

Usually not. The uninstallers only delete things they can positively recognize as having been created by the matching installer. If they find something with a similar name that they cannot prove is theirs, for example a different program that is also called `flow`, they leave it alone and tell you, so they never delete something that was not theirs. Each of these lines says why it was left. The other common reason is that something could not be checked, for example because Docker was not running. In that case, start Docker and run the uninstaller again.

### I installed ResInsight into a custom folder. Will the uninstaller find it?

Not automatically, because the installer does not remember where it installed. Tell the uninstaller the same folder you gave the installer: `--install-root FOLDER` on Linux and macOS, `-InstallRoot FOLDER` on Windows. If the uninstaller finds nothing in the default location but sees that your `resinsight` command or shortcut points somewhere else, it prints that location so you know what to give it.

### Is it safe to run an uninstaller twice?

Yes. Each part is checked separately, so running it a second time just removes whatever the first run could not (for example Docker images, because Docker was switched off), or says there is nothing left to remove.

### Can I undo an uninstall?

Run the installer again. Anything that was removed is installed again from scratch. One thing to know: if you did not use `--keep-images` (or `-KeepImages`) or `--keep-cache` (or `-KeepCache`), the OPM Flow Docker image or the ResInsight download will have to be downloaded again, which can take a while.

## Troubleshooting in general

### I followed all the steps and it still does not work. What now?

Please open an issue so we can help directly. See [ISSUE.md](ISSUE.md) for exactly what information to include, it will help us solve your problem much faster if you follow the template there rather than just describing the problem in a sentence or two.

### Is there a faster way to get help than opening an issue?

Opening an issue with full details, as described in [ISSUE.md](ISSUE.md), is currently the best way. It creates a record that others with the same problem can also find and benefit from, rather than the answer only reaching one person.

### I found a typo or unclear instruction in the README. Should I open an issue for that too?

Yes, or even better, see [CONTRIBUTING.md](CONTRIBUTING.md) for how to suggest the fix yourself.
