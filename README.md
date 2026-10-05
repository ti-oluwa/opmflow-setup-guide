# OPM Flow and ResInsight installers

This repository has simple setup scripts for two tools used in reservoir simulation work:

1. **OPM Flow**, a reservoir simulator, installed and run through Docker.
2. **ResInsight**, a 3D viewer for looking at simulation results, installed as a normal desktop application.

There are four setup scripts in total. Two for OPM Flow (one for Linux and macOS, one for Windows) and two for ResInsight (same split). You only need to run the ones for your own operating system and the tool you want.

| Script | What it installs | Platform |
|---|---|---|
| `opmflow-setup.sh` | OPM Flow (via Docker) | Linux and macOS |
| `opmflow-setup.ps1` | OPM Flow (via Docker) | Windows |
| `resinsight-setup.sh` | ResInsight (desktop app) | Linux and macOS |
| `resinsight-setup.ps1` | ResInsight (desktop app) | Windows |

Each of them also has a matching uninstall script, in case you want to remove a tool again later. Those are covered in [Part 3: Uninstalling](#part-3-uninstalling).

| Script | What it removes | Platform |
|---|---|---|
| `opmflow-uninstall.sh` | OPM Flow | Linux and macOS |
| `opmflow-uninstall.ps1` | OPM Flow | Windows |
| `resinsight-uninstall.sh` | ResInsight | Linux and macOS |
| `resinsight-uninstall.ps1` | ResInsight | Windows |

This README is written as a full tutorial. It assumes you might not be comfortable with the command line yet, especially if you are on Windows, so it walks through everything step by step, including what the buttons and words mean. If you already know your way around a terminal, feel free to skip ahead using the table of contents below.

If something in this guide does not work for you, that is useful information for us, not a failure on your part. See the [Reporting a problem](#reporting-a-problem) section near the end for how to tell us about it in a way that helps us fix it fast.

## Table of contents

- [Security disclaimer, please read this first](#security-disclaimer-please-read-this-first)
- [Glossary: words used in this guide](#glossary-words-used-in-this-guide)
- [Getting the scripts onto your computer](#getting-the-scripts-onto-your-computer)
- [Part 1: OPM Flow](#part-1-opm-flow)
  - [What OPM Flow is](#what-opm-flow-is)
  - [What the installer actually does](#what-the-installer-actually-does)
  - [OPM Flow on Linux and macOS](#opm-flow-on-linux-and-macos)
  - [OPM Flow on Windows](#opm-flow-on-windows)
  - [Using OPM Flow after install](#using-opm-flow-after-install)
  - [Where OPM Flow can see your files](#where-opm-flow-can-see-your-files)
- [Part 2: ResInsight](#part-2-resinsight)
  - [What ResInsight is](#what-resinsight-is)
  - [What the installer actually does](#what-the-resinsight-installer-actually-does)
  - [ResInsight on Linux and macOS](#resinsight-on-linux-and-macos)
  - [ResInsight on Windows](#resinsight-on-windows)
- [Part 3: Uninstalling](#part-3-uninstalling)
  - [Before you uninstall](#before-you-uninstall)
  - [What gets removed, and what never does](#what-gets-removed-and-what-never-does)
  - [Getting the uninstall scripts](#getting-the-uninstall-scripts)
  - [Preview first with a dry run](#preview-first-with-a-dry-run)
  - [Uninstalling OPM Flow on Linux and macOS](#uninstalling-opm-flow-on-linux-and-macos)
  - [Uninstalling OPM Flow on Windows](#uninstalling-opm-flow-on-windows)
  - [Uninstalling ResInsight on Linux and macOS](#uninstalling-resinsight-on-linux-and-macos)
  - [Uninstalling ResInsight on Windows](#uninstalling-resinsight-on-windows)
  - [Removing Docker and WSL2 yourself (optional)](#removing-docker-and-wsl2-yourself-optional)
  - [How the uninstallers keep your computer safe, for the curious](#how-the-uninstallers-keep-your-computer-safe-for-the-curious)
- [Frequently asked questions](#frequently-asked-questions)
- [Reporting a problem](#reporting-a-problem)
- [Contributing](#contributing)

## Security disclaimer, please read this first

These scripts download files from the internet (Docker images, ResInsight releases) and install software on your computer. Some steps need administrator access (`sudo` on Linux and macOS, an elevated PowerShell on Windows) because installing software and adding programs to your system's PATH requires it.

We have reviewed these scripts carefully and, as far as we can tell, they do not contain anything malicious. That said, no one can promise you with total certainty that any script, from any source, including this one, is 100 percent safe. This is true of every script you will ever download from the internet, not just this one. Before running any script with administrator rights, it is good practice to:

- Read through the script yourself first if you are able to, even if you do not understand every line.
- Only run scripts from sources you trust.
- Keep a backup of anything important before installing new software.

You are responsible for what you run on your own computer. We are not able to accept liability for any damage, data loss, or other issues that come from using these scripts. If you are not comfortable running a script with elevated permissions, you can also follow the official Docker and ResInsight installation guides linked further down and skip the automation entirely.

## Glossary: words used in this guide

If some of these words are new to you, read through this section once before you start. You do not need to memorize it, just skim it so the later steps make sense.

**Terminal (also called command line, console, or shell):** A window on your computer where you type instructions as text instead of clicking on icons. It looks plain and a bit intimidating at first, but it is just a very direct way of talking to your computer.

**Command Prompt:** An older, basic terminal program that comes built into Windows. You can open it by pressing the Windows key, typing `cmd`, and pressing Enter.

**PowerShell:** A newer, more capable terminal program that also comes built into Windows. Most of the steps in this guide for Windows use PowerShell rather than Command Prompt, because it can do more and our Windows scripts are written for it.

**Bash / shell:** The program that reads and runs the commands you type into a terminal on Linux and macOS. When this guide says "open a terminal" on Linux or macOS, this is what you are talking to.

**Script:** A plain text file full of commands that your computer reads and runs one after another automatically, instead of you typing each command yourself. The `.sh` and `.ps1` files in this repository are scripts.

**Repository (repo):** A folder of files, usually code, stored online (commonly on a site called GitHub) that other people can look at or download.

**Clone:** Downloading a full copy of a repository using a tool called `git`, including its entire history. You do not need to clone this repository to use it. See [Getting the scripts onto your computer](#getting-the-scripts-onto-your-computer) below for a simpler way.

**Docker:** A program that lets you run other software inside a sealed, self-contained box called a container. Instead of installing OPM Flow and all the specific library versions it needs directly onto your computer, Docker downloads a ready-made package (an image) and runs it in isolation. This means OPM Flow runs the same way on your machine as it does on anyone else's, without you having to hand-install a long list of dependencies.

**Docker image:** The template or blueprint that a container is built from. Images are downloaded ("pulled") from an online registry, similar to how you would download an app from an app store.

**Docker container:** A running copy of an image. When you run OPM Flow through Docker, Docker starts a container from the OPM Flow image, runs your simulation inside it, and then that container stops.

**Docker Desktop:** The application that runs Docker on Windows and macOS, with a small icon in your system tray or menu bar. On Linux, Docker runs as a background service instead and does not need a separate desktop app.

**WSL / WSL2 (Windows Subsystem for Linux):** A feature built into Windows that lets it run a real Linux system alongside your normal Windows desktop. Docker Desktop on Windows needs WSL2 to be installed first, because Docker containers are Linux-based under the hood even when you are running them from Windows.

**sudo:** A command on Linux and macOS that means "run this next command as the administrator." Many install steps need this because they change system-level files that a normal user account is not allowed to touch on its own.

**Administrator / elevated terminal (Windows):** The Windows equivalent of `sudo`. Instead of putting a word in front of a command, you open PowerShell itself in a special mode that grants it permission to make system-level changes. Steps below tell you exactly when you need this.

**PATH:** A list of folders that your computer checks through whenever you type a command by name. If a program's folder is "on your PATH," you can run it from anywhere just by typing its name. If it is not, you have to type the full location of the program every time, or click into that folder first.

**Execution policy (PowerShell only):** A safety setting in Windows that can stop scripts from running unless you explicitly allow it, similar to a car's parental lock. It exists so that a script cannot silently run just because you double-clicked it or downloaded it by accident. We show you the exact command to allow it for the one script you are running.

**Package manager:** A tool that installs and updates other software for you automatically, instead of you hunting down installers yourself. Examples used in this guide are `apt` (Ubuntu and Debian), `dnf` and `yum` (Fedora and RHEL-based systems), `Homebrew` (macOS), and `winget` (Windows).

**Shortcut / symlink:** A pointer to a program that lives somewhere else, so you can launch it from an easier place (like your Start Menu or desktop) without knowing its real file location.

**Environment variable:** A named value that your terminal session or your whole computer keeps track of, which programs can read. Some steps in this guide ask you to set one before running a command, for example `OPM_FLOW_EXTRA_MOUNTS=/some/path flow CASE.DATA`. Setting it this way only affects that one command; it does not change your computer's settings permanently.

**Uninstaller:** A script that removes what an installer put on your computer, the way "Uninstall" in your system settings removes an ordinary app. The scripts in Part 3 are uninstallers.

**Dry run:** Running a script in a mode where it shows you what it would do, but does not actually do any of it. It is a rehearsal. Every uninstall script has one, and it is the safest way to see what a script will do before you let it.

**Flag (also called an option):** An extra word you add after a command to change how it behaves, for example `--dry-run` or `-DryRun`. Flags start with one or two dashes.

**Cache:** A folder where a program keeps files it downloaded, so it does not have to download them again next time. Deleting a cache never breaks anything. It only means the files get downloaded again if they are needed.

## Getting the scripts onto your computer

You do not need to know `git` or clone anything to use these scripts. Here are three ways to get a single script file onto your computer, from easiest to most advanced.

### Option A: Download a single file from your browser (easiest)

1. Go to the repository's page in your web browser.
2. Click on the script file you need, for example `opmflow-setup.sh`.
3. Look for a button labeled **Raw** (sometimes shown as `</>` or "View raw"). Click it.
4. Your browser will either show you the plain text of the script, or start a download automatically.
   - If it shows plain text: right-click anywhere on the page and choose **Save As** (or **Save Page As**), then save it. Make sure the file name still ends in `.sh` or `.ps1`, not `.txt`.
   - If it downloads automatically: check your Downloads folder for the file.
5. Move the downloaded file to a folder you will remember, for example a new folder called `opm-tools` in your home folder or Documents.

**What can go wrong here:** if the saved file ends up named something like `opmflow-setup.sh.txt`, rename it back to `opmflow-setup.sh` (remove the `.txt` part). Some browsers add this automatically when saving plain text. On Windows, you may need to turn on "show file extensions" in File Explorer first to even see the `.txt` part. You can do this from File Explorer's **View** menu, by checking **File name extensions**.

### Option B: Download with a terminal command

If you already have a terminal open, this is often faster than clicking through a browser.

On Linux or macOS:

```bash
curl -O https://raw.githubusercontent.com/ti-oluwa/opmflow-setup-guide/refs/heads/main/scripts/opmflow-setup.sh
```

On Windows, in PowerShell:

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/ti-oluwa/opmflow-setup-guide/refs/heads/main/scripts/opmflow-setup.ps1 -OutFile opmflow-setup.ps1
```

Swap the `<filename>` in `https://raw.githubusercontent.com/ti-oluwa/opmflow-setup-guide/refs/heads/main/scripts/<filename>` with the name of whichever of the scripts you need (Do not forget to include the file extension in the file name - ".ps1" or ".sh").

### Option C: Clone the whole repository (if you already use git)

```bash
git clone https://github.com/ti-oluwa/opmflow-setup-guide.git
cd opmflow-setup-guide
```

All the scripts (the setup scripts and the uninstall scripts) will now be in that folder - `opmflow-setup-guide/scripts`, together.

## Part 1: OPM Flow

### What OPM Flow is

OPM Flow is a reservoir simulator. In plain terms, it is a program that takes a description of an oil or gas reservoir (rock properties, wells, fluids, and so on, usually written in a file ending in `.DATA`) and calculates how that reservoir would behave over time, for example how pressure and fluid flow change as wells produce or inject.

OPM Flow is normally distributed as source code that you would have to compile yourself, along with a specific set of supporting libraries. That is a lot of setup for something you just want to run. This is exactly the kind of problem Docker solves: instead of building OPM Flow and its dependencies by hand, you download a ready-made Docker image that already has everything set up correctly inside it, and you just run it.

### What the installer actually does

Here is the short version, before we get into the step by step walkthrough. Both `opmflow-setup.sh` and `opmflow-setup.ps1` do roughly the same four things:

1. Check whether Docker is installed on your computer. If it is not, the script tries to install it for you.
2. Make sure Docker is actually running (not just installed).
3. Download ("pull") the OPM Flow Docker image, picking the correct version for your version and processor type automatically.
4. Install two small commands, `opmflow` and `flow`, so that from then on you can just type `flow SPE1.DATA` in any terminal to run a simulation, instead of typing a long Docker command by hand every time.

We will go through each of these in detail below, separately for Linux and macOS, and for Windows, because the exact steps and possible errors are different enough on each platform to be worth covering on their own.

### OPM Flow on Linux and macOS

This section covers `opmflow-setup.sh`. It works on both Linux and macOS, but a few steps differ between the two, and we will call those out clearly as we go.

#### Step 1: Open a terminal

- **On Linux:** most desktop environments let you open a terminal by pressing `Ctrl + Alt + T`, or by searching for "Terminal" in your applications menu.
- **On macOS:** press `Cmd + Space` to open Spotlight, type `Terminal`, and press Enter.

You should see a mostly empty window with some text and a blinking cursor, waiting for you to type something.

#### Step 2: Go to the folder where you saved the script

If you saved `opmflow-setup.sh` in your Downloads folder, for example, type:

```bash
cd ~/Downloads
```

and press Enter. `cd` means "change directory," which is the terminal's way of saying "go into this folder." The `~` is a shortcut for your home folder.

**What can go wrong here:** if you get a message like `No such file or directory`, you likely saved the script somewhere else, or renamed the folder. Use your file manager (Finder on macOS, Files on most Linux desktops) to actually locate the file first, then use `cd` to go to that exact folder.

#### Step 3: Make the script executable

Scripts you download are not allowed to run by default, as a safety measure. You need to explicitly mark the file as runnable:

```bash
chmod +x opmflow-setup.sh
```

`chmod` changes a file's permissions, and `+x` means "add the ability to execute this file." Nothing will appear to happen after you run this. That is normal.

**What can go wrong here:** if you get `chmod: cannot access 'opmflow-setup.sh': No such file or directory`, you are not in the folder where the file actually is. Go back to Step 2.

#### Step 4: Run the script with sudo

```bash
sudo ./opmflow-setup.sh
```

You will be asked for your account password. This is normal. It will not show any characters or dots as you type, which is also normal, it is a security habit of the terminal, not a bug. Type your password and press Enter.

We need `sudo` here because the script installs Docker system-wide if it is missing, and it adds the `flow` and `opmflow` commands to a system folder (`/usr/local/bin`) so that they work for anyone who uses your computer, not just your current login session.

**What can go wrong here:**

- `sudo: ./opmflow-setup.sh: command not found`, this usually means you skipped Step 3. Go back and run `chmod +x opmflow-setup.sh` first.
- `Sorry, try again`, repeated a few times, then locking you out: you are typing your password wrong. Type slowly and carefully, remembering that nothing will appear to show your keystrokes.
- If your account does not have `sudo` access at all (some shared or work computers restrict this), you will see something like `your-username is not in the sudoers file`. In that case you will need to ask whoever manages the computer to either run the script for you or grant your account `sudo` access.

#### Step 5: Let the script handle Docker

Once running, the script checks if Docker is already on your system. If it is not, it tries to install it automatically, using whichever package manager your system already has (`apt` on Ubuntu and Debian, `dnf` or `yum` on Fedora and RHEL-based systems, `pacman` on Arch, `zypper` on openSUSE, or Homebrew on macOS). You should see log lines starting with `[opm-flow]` describing what it is doing.

This step can take a few minutes the first time, especially on a slower internet connection, since Docker itself is a fairly large piece of software.

##### If you would rather install Docker yourself first

You do not have to let the script install Docker for you. If you would rather do it manually, or the automatic install does not work for your specific Linux distribution, here is how.

**Official guide:** Docker's own installation instructions are always the most accurate and up to date source, and cover essentially every Linux distribution and macOS: [https://docs.docker.com/get-started/get-docker/](https://docs.docker.com/get-started/get-docker/)

**Video walkthrough (Linux):** if you prefer to watch someone do it step by step, here is a clear tutorial for installing Docker on Ubuntu, or similar Debian-based distributions too.

[![Easily Install Docker on Linux and Run Your First Container, step by step video guide](https://img.youtube.com/vi/FvdlwyMwrzg/maxresdefault.jpg)](https://www.youtube.com/watch?v=FvdlwyMwrzg)

*(Click the thumbnail to watch on YouTube: "Easily Install Docker on Linux and Run Your First Container | Step-by-Step Guide")*

**On macOS**, Docker is installed as an application called Docker Desktop, not through the terminal. The simplest way is:

1. Go to [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/) and download Docker Desktop for Mac, choosing the version that matches your chip (Apple Silicon or Intel, see the note below on checking this).
2. Open the downloaded file and drag the Docker icon into your Applications folder, as instructed on screen.
3. Open Docker Desktop from your Applications folder. The first time you do this, macOS will likely warn you that it was downloaded from the internet. Click **Open** to proceed. This is Apple's Gatekeeper security feature doing its job, not an error.
4. Wait for the little whale icon in your menu bar to stop animating and settle into place. That means Docker is ready.

If you are not sure whether your Mac has Apple Silicon (M1, M2, M3, or newer) or an Intel chip, click the Apple logo in the top left of your screen, choose **About This Mac**, and look at the chip name listed there.

Alternatively, if you already have Homebrew installed (a popular package manager for macOS), you can install Docker Desktop with:

```bash
brew install --cask docker
```

then open it once from your Applications folder to finish the setup, the same as above.

##### macOS specific note: Homebrew and running as a regular user

If you let the script install Docker for you on macOS, it needs Homebrew to already be installed, since that is what it uses to install Docker Desktop. If Homebrew is missing, the script will stop and tell you to install it first from [https://brew.sh](https://brew.sh).

You might also notice the script asking to run parts of the Homebrew install as your normal user account, even though you started the whole script with `sudo`. This is intentional and not a bug. Homebrew refuses to run as the administrator (root) user, on purpose, since it manages your personal Applications folder. The script detects this and quietly runs just that one step as you, the original user, while still running the rest of the install with the elevated permissions it needs.

#### Step 6: The script makes sure Docker is actually running

Being installed and being running are two different things, the same way having a car in your garage does not mean the engine is on. The script checks for this and, if needed, starts Docker for you.

- **On Linux**, Docker runs as a background service. The script starts it using `systemctl`, which is the standard tool for managing background services on most modern Linux systems.
- **On macOS**, Docker runs as the Docker Desktop application. The script opens it for you if it is not already running, then waits, checking every few seconds, until it reports that it is ready. This can take up to a minute or two the first time, since Docker Desktop has some setup work to do on its first launch.

**What can go wrong here:**

- On Linux, if you see something about `systemctl` not being found at all, your system may not use `systemd` (some minimal or specialized Linux distributions do not). In that case you will need to start the Docker service using whatever your distribution provides instead, and the automatic parts of this script will not fully apply to you.
- On macOS, if the script waits and then times out with a message that Docker did not become ready, check if a Docker Desktop window popped up needing you to accept its license terms or grant it permissions in System Settings. Handle that, then run the script again.
- On macOS, if you see a message about needing to approve a "privileged helper" the first time, this is Docker Desktop asking for a one-time permission through the normal macOS system prompt. Approve it, and re-run the script if it did not continue on its own.

#### Step 7: Downloading the OPM Flow image

The script now downloads the actual OPM Flow Docker image. It automatically figures out the right version for your processor (Intel and AMD-based machines use one version, Apple Silicon and other ARM-based machines use another), so you generally do not need to think about this at all.

You will see log lines about pulling an image, with a name like `openporousmedia/opmreleases:2026.04_amd64`. This can take a few minutes depending on your internet speed, since these images can be a few hundred megabytes or more.

**What can go wrong here:** if this step fails with something about not being able to reach the registry, check your internet connection. If you are on a work or restricted network, it is possible that outbound access to Docker Hub is blocked by a firewall, in which case you will need to ask whoever manages your network to allow it, or download the image on a different network and transfer it.

#### Step 8: The script installs the `flow` and `opmflow` commands

Once the image is downloaded, the script writes two small command files into `/usr/local/bin`, a standard folder that is already on most Linux and macOS systems' PATH. This is what lets you type `flow SPE1.DATA` from anywhere afterward, instead of a long Docker command.

At the end, the script runs a quick check by asking OPM Flow to report its own version, to confirm everything actually works before declaring success. You should see a message like:

```text
[opm-flow] OPM Flow installation completed.
```

If you see that, you are done.

#### How it works, for the curious ones

If you are happy just using the tool, you can skip this part. If you want to understand what is actually happening behind the log lines, here is the fuller picture.

The script is a "wrapper installer." It does not just download one file, it writes a second, smaller script (also called `opmflow` or `flow`) into `/usr/local/bin`. That second script is what actually runs every time you type `flow SPE1.DATA`. What it does, in order, is:

1. Read a small configuration file at `/etc/opm-flow/config`, which stores which OPM Flow version and image you have pinned.
2. Check whether that exact Docker image is already downloaded on your machine. If not, download it.
3. Run `docker run`, passing your current folder into the container as a mounted folder, so OPM Flow can see and write files right where you are working, not somewhere hidden inside the container.
4. Pass along any extra arguments you typed (like your `.DATA` file name) straight through to OPM Flow inside the container.

Because the actual OPM Flow version is stored in that config file rather than hardcoded into the `flow` command itself, you can later switch versions without reinstalling anything, using `sudo opmflow upgrade` or `sudo opmflow configure --variant VARIANT`. Both of those are covered in [Using OPM Flow after install](#using-opm-flow-after-install).

The installer also avoids doing unnecessary work. Before downloading anything, it checks if the exact image you are asking for is already sitting on your computer, and if it is, it skips the download entirely. When it does need to check whether a specific version exists at all, it uses a lightweight check (`docker manifest inspect`) that just asks "does this exist," rather than starting a full download and then throwing it away if you did not actually want that version.

### OPM Flow on Windows

This section covers `opmflow-setup.ps1`. Windows needs a few extra pieces before Docker can even run, mainly WSL2, so we will walk through those first. If you already have Docker Desktop working on Windows, you can skip ahead to [Step 4](#step-4-open-powershell).

#### Understanding what you need on Windows, in order

1. **WSL2** (Windows Subsystem for Linux). Docker containers are Linux-based under the hood, so even on Windows, Docker needs a real Linux environment to actually run them in. WSL2 provides that.
2. **Docker Desktop**. The actual application that manages Docker on your Windows machine, built on top of WSL2.
3. **This script**, which then downloads the OPM Flow image and sets up the `flow` and `opmflow` commands, the same as on Linux and macOS.

We will go through installing WSL2 first, then Docker Desktop, then running the script itself. If you already have both WSL2 and Docker Desktop installed and working, you can skip straight to running the script.

#### Step 1: Install WSL2

The fastest way is a single command. You can use either PowerShell or Command Prompt for this specific step, since the command is the same in both.

1. Open the Start menu, type `PowerShell`, right-click on **Windows PowerShell**, and choose **Run as administrator**. Click **Yes** on the permissions prompt that appears.
2. Type this command and press Enter:

```bash
wsl --install
```

1. Wait for it to finish. It will download and set up WSL2 along with a default Linux distribution (usually Ubuntu).
2. Restart your computer when it asks you to. This step is not optional, WSL2 needs the restart to finish setting itself up.
3. After restarting, a window may open asking you to create a username and password for your new Linux environment. This is separate from your Windows login, and can be anything you like. Write it down somewhere, you may need it again later.

**Alternative: installing a Linux distribution through the Microsoft Store.** If the command above does not work for you, or you would rather use a graphical method:

1. Open the **Microsoft Store** app from your Start menu.
2. Search for **Ubuntu** (or another distribution of your choice, Ubuntu is a safe default if you are not sure).
3. Click **Get** or **Install**.
4. Once installed, open it from your Start menu. It will ask you to set up a username and password the first time, the same as above.
5. This method still needs WSL2 itself to be enabled first. If you have not already run `wsl --install` as shown above, open PowerShell as Administrator and run `wsl --set-default-version 2`, then try opening your installed distribution again.

**Video walkthrough:** here is a clear, current walkthrough of installing WSL2 on Windows 11 from scratch.

[![How to install Linux on Windows 11 with WSL for Beginners, step by step video guide](https://img.youtube.com/vi/zZf4YH4WiZo/maxresdefault.jpg)](https://www.youtube.com/watch?v=zZf4YH4WiZo)

*(Click the thumbnail to watch on YouTube: "How to install Linux on Windows 11 with WSL for Beginners (Step-by-Step Tutorial)")*

**What can go wrong here:**

- **"WSL requires Virtual Machine Platform to be enabled"** or a similar message: this usually means virtualization is turned off in your computer's BIOS or UEFI settings. This is a low-level setting outside of Windows itself, and how to reach it varies by computer manufacturer, but it is usually done by pressing a key like `F2`, `F10`, `Del`, or `Esc` right when your computer is starting up, before Windows loads, then looking for a setting called **Virtualization Technology**, **Intel VT-x**, or **AMD-V**, and turning it on.
- **"The requested operation requires elevation"**: you opened PowerShell normally instead of as Administrator. Close it and reopen it using **Run as administrator** as described in Step 1.
- **Nothing happens, or it hangs for a very long time**: check your internet connection, since this command downloads files. If it has genuinely frozen for many minutes with no progress, closing the window and trying again is usually safe.
- **Windows says your version of Windows is too old**: WSL2 needs a reasonably recent version of Windows 10 or Windows 11. Open **Settings > Windows Update** and install any pending updates, then try again.

#### Step 2: Install Docker Desktop

1. Go to [https://docs.docker.com/desktop/setup/install/windows-install/](https://docs.docker.com/desktop/setup/install/windows-install/) and download Docker Desktop for Windows.
2. Run the downloaded installer. Keep the default option to use the **WSL2 backend** checked, since that is what this script and OPM Flow's images expect.
3. Once installation finishes, it will likely ask you to log out or restart. Do so if asked.
4. Open Docker Desktop from your Start menu. The first time you open it, it may ask you to accept a license agreement, and possibly to sign in or create a free Docker account (you can also usually skip the sign-in step and continue without an account).
5. Wait for Docker Desktop's window to show that the engine is running. This is usually shown as a green indicator or a message near the bottom left of the window.

**Video walkthrough:**

[![How to Install Docker Desktop on Windows 11, step by step video guide](https://img.youtube.com/vi/fOZfMqM4MIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=fOZfMqM4MIA)

*(Click the thumbnail to watch on YouTube: "How To Install Docker Desktop On Windows 11 (Easy Guide)")*

**What can go wrong here:**

- **"WSL 2 installation is incomplete"**: go back to Step 1 and make sure `wsl --install` finished successfully and you restarted your computer afterward.
- **Docker Desktop opens but never finishes starting**: quit it completely (right-click its icon in your system tray, near the clock, and choose Quit), then reopen it. If that does not help, restarting your computer usually does.
- **You do not have an available Docker account and do not want to make one**: this is fine, Docker Desktop can be used without signing in. Look for a "skip" or "continue without signing in" option on the login screen.

#### Step 3: Skip this if you do not need Docker's own Linux container mode confusion

Docker Desktop can run in two modes: Linux containers or Windows containers. OPM Flow's images are Linux-based, so you need Linux containers mode, which is the default for almost everyone. You generally do not need to touch this setting. If our script ever detects you are in the wrong mode, it will tell you exactly what to click to fix it (right-click the Docker icon in your system tray and choose "Switch to Linux containers").

#### Step 4: Open PowerShell

Open the Start menu, type `PowerShell`, and open it normally this time. You do not need Administrator rights for most of this script, since it installs itself per-user rather than system-wide. The one exception is explained in the note below.

#### Step 5: Go to the folder where you saved the script

If you saved `opmflow-setup.ps1` in your Downloads folder:

```powershell
cd $HOME\Downloads
```

**What can go wrong here:** if PowerShell says it cannot find the path, double check exactly where you saved the file using File Explorer, then adjust the folder name in the command to match.

#### Step 6: Allow the script to run

Windows blocks scripts from running by default as a security measure, called the execution policy. You need to allow it just for this one script, in just this one PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File .\opmflow-setup.ps1
```

This runs the script once, bypassing the block only for this run, without permanently changing any Windows security settings. If you prefer, you can instead change the policy for your whole session and then run the script normally:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\opmflow-setup.ps1
```

Either approach works. The first one is slightly simpler if you are only doing this once.

**What can go wrong here:**

- **"cannot be loaded because running scripts is disabled on this system"**: this is exactly the execution policy protection described above. Use one of the two commands shown just above instead of just typing `.\opmflow-setup.ps1` directly.
- **"The term '.\opmflow-setup.ps1' is not recognized..."**: you are not in the folder where the script actually is. Go back to Step 5.

#### Step 7: Let the script install Docker if needed

If Docker Desktop is not already installed (you can skip this if you already did Step 2 above), the script tries to install it automatically using `winget`, a package manager that comes built into modern Windows.

**What can go wrong here:**

- **"winget was not found"**: your version of Windows is old enough that `winget` is not included. Install Docker Desktop manually using Step 2 above, then run the script again, it will detect Docker is already there and skip straight past this step.
- **A Windows security prompt (UAC) appears asking to allow changes**: this is expected, since installing Docker Desktop needs administrator rights even if the rest of this script does not. Click **Yes**.
- **The script warns that WSL2 does not appear to be set up**: go back to Step 1 above and complete it, including the restart, before continuing.

#### Step 8: The script waits for Docker to be ready, downloads the image, and installs the commands

This is the same as Steps 6 through 8 in the Linux and macOS walkthrough above, just running through PowerShell instead. The script waits for Docker's engine to report it is running, downloads the correct OPM Flow image for your processor, and then installs the `flow` and `opmflow` commands.

Unlike on Linux and macOS, these commands are installed per-user, into a folder under `$env:LOCALAPPDATA`, and added to your personal PATH rather than a system-wide one. This means you generally do not need Administrator rights for this part, only for the earlier Docker Desktop install step if it was needed.

**What can go wrong here:**

- **You ran the script, it finished, but typing `flow` says it is not recognized**: PowerShell only reloads your PATH when a new window opens. Close your PowerShell window and open a fresh one, then try `flow --version` again.
- **The final check fails with an error about running Flow**: this usually means Docker was not fully ready yet when the script tried to use it. Wait a minute for Docker Desktop to finish starting completely (check its window or tray icon), then run the script again, it will skip the parts that already succeeded.
- **The script fails with an error saying that script execution is not allowed**: PowerShell's execution policy is preventing the installer from running. Run `Get-ExecutionPolicy -List` to check the current policies, then run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` to allow locally run scripts for your user. Rerun the last command to start the installer again.

#### How it works, for the curious

The Windows version works the same way as the Linux and macOS version described earlier, with one structural difference worth knowing about: instead of creating a shortcut or a link the way Linux uses `ln`, this script generates two small files for each command, a `.ps1` file (for PowerShell) and a matching `.cmd` file (so the same command also works from the older Command Prompt). Both just forward whatever you typed straight through to Docker.

Windows also has no concept of Linux's file permission numbers (the ones Linux uses to decide who is allowed to run a file), and no single administrator account the way Linux has `root`. Because of that, this script deliberately avoids needing Administrator rights for anything except installing Docker Desktop itself, and stores its configuration and commands in your own personal user folder rather than a shared system one.

### Using OPM Flow after install

Once installed, running a simulation looks the same on every platform:

```bash
flow SPE1.DATA
```

Replace `SPE1.DATA` with the path to your own reservoir description file. If the file name has spaces in it, wrap it in quotes:

```bash
flow "My Field.DATA"
```

A small but important note for Windows users specifically: PowerShell's escape character (the symbol used to tell it "treat the next character literally") is the backtick, `` ` ``, not the backslash `\` the way it is in Linux and macOS terminals. If you are used to typing something like `My\ Field.DATA` on Linux to handle the space, that will not work the same way in PowerShell. Just use double quotes instead, as shown above, and you will not need to think about escape characters at all.

A few other commands you can use any time after install:

```bash
opmflow version      # shows which OPM Flow version is currently installed
opmflow image         # shows the exact Docker image being used
opmflow variant        # shows which build variant (amd64, arm64, and so on) is active
opmflow config          # shows your full current configuration
```

On Linux and macOS, changing your version or variant needs `sudo`, since it writes to a shared system configuration file:

```bash
sudo opmflow upgrade              # switches to the latest available version
sudo opmflow upgrade 2026.04       # switches to a specific version
sudo opmflow configure --variant amd64   # switches to a specific build variant
```

On Windows, the same commands work without needing an elevated PowerShell, since configuration is stored per-user:

```bash
opmflow upgrade
opmflow upgrade 2026.04
opmflow configure --variant amd64
```

### Where OPM Flow can see your files

This part matters more than it might seem, so we will address it in this section.

When you run `flow SPE1.DATA`, OPM Flow is not actually running directly on your computer. It is running inside a Docker container, a sealed box, as explained in the glossary above. By default, the only folder from your computer that OPM Flow can see and use inside that box is the one you are standing in when you type the command (your current folder), along with anything inside it.

In practice, this means: **your `.DATA` file, and every other file it refers to with an `INCLUDE` statement, need to live in the folder you are running `flow` from, or in a subfolder inside it.** If your `.DATA` file tries to `INCLUDE` a file from somewhere else entirely on your computer, for example a shared properties file kept in a different project folder, OPM Flow will not be able to find it, even though the file genuinely exists on your machine.

**Why it works this way, rather than just giving OPM Flow access to your whole computer.** This will get asked fairly often, so here is the honest reasoning. It would be technically possible to make the container able to see your entire hard drive instead of just one folder. We chose not to do that, on purpose, for a simple reason: OPM Flow's Docker image comes from a third party, not from us, and handing it read and write access to every file on your computer (your documents, your photos, your other projects, everything) is a much bigger risk than it looks. If there were ever a bug in OPM Flow itself, or a problem with the image at its source, the damage that could cause would be limited to just the one folder you are working in, rather than your whole machine. For the ordinary case, where a simulation case's files all live together in one project folder, this restriction costs you nothing. It only becomes a question when a case genuinely needs a file from somewhere else.

**If you do have files outside your working folder that a case needs**, you do not need to move them, and you do not need to widen access to your whole computer either. Set the `OPM_FLOW_EXTRA_MOUNTS` environment variable before running `flow`, and it will let OPM Flow see exactly the extra folders you list, and nothing more.

On Linux and macOS:

```bash
OPM_FLOW_EXTRA_MOUNTS=/data/shared flow CASE.DATA
```

This makes `/data/shared` visible inside the container at the exact same path, so a file your `.DATA` deck already refers to as `/data/shared/props.inc` will simply work, with nothing to change in the deck itself.

If you would rather it show up at a different path inside the container, or you need more than one extra folder, you can be more specific:

```bash
OPM_FLOW_EXTRA_MOUNTS=/data/pvt=/mnt/pvt flow CASE.DATA
OPM_FLOW_EXTRA_MOUNTS=/data/a:/data/b flow CASE.DATA
```

Paths are separated with a colon (the same character your PATH variable already uses), and `=` lets you choose a different path inside the container than on your own computer.

On Windows, the idea is the same, but the exact syntax is a little different, because Windows paths already use a colon for the drive letter (like `C:\`), so semicolons separate multiple entries instead, and you always have to say exactly where the folder should appear inside the container, since there is no automatic "same path" translation from a Windows path into a Linux one:

```powershell
$env:OPM_FLOW_EXTRA_MOUNTS = "C:\data\shared=/data/shared"
flow CASE.DATA
```

```powershell
$env:OPM_FLOW_EXTRA_MOUNTS = "C:\data\a=/data/a;C:\data\b=/mnt/b"
flow CASE.DATA
```

Setting an environment variable this way only applies to that one PowerShell window and the commands you run in it afterward. It does not change any permanent Windows setting, and closing the window forgets it, so you would need to set it again next time if you use it regularly.

**What can go wrong here:**

- **A path listed in `OPM_FLOW_EXTRA_MOUNTS` does not exist**: the script checks each path before using it and simply skips (with a warning) anything it cannot find, rather than failing the whole simulation. Double check the exact path for typos if a file still is not found inside the container.
- **You forgot to say where a folder should go inside the container on Windows**: unlike Linux and macOS, Windows requires the `=CONTAINER_PATH` part every time. If you leave it out, you will see a clear warning telling you the entry was skipped and why.
- **Files still are not found even after setting this**: double check that the path used inside your `.DATA` file's `INCLUDE` statement matches the container-side path exactly, not the original path on your own computer, if the two are different.

## Part 2: ResInsight

### What ResInsight is

ResInsight is a 3D viewer built for looking at and analyzing reservoir simulation results, including the ones produced by OPM Flow. Where OPM Flow does the number crunching, ResInsight is what you actually look at afterward, letting you see the reservoir in 3D, plot production curves, and inspect results visually.

Unlike OPM Flow, ResInsight is installed as a normal desktop application, not through Docker. This is because it is a graphical program you interact with directly (windows, mouse, menus), while OPM Flow is a background calculation tool with no visual interface of its own.

### What the ResInsight installer actually does

Both `resinsight-setup.sh` and `resinsight-setup.ps1` do the following:

1. Ask GitHub which files (assets) are available for the ResInsight version you asked for (or the latest one, by default).
2. Pick out the one that matches your operating system and processor.
3. Download it, keeping a local copy so it does not need to download the same thing twice.
4. Unpack it and install it in the right place for your system.
5. Set things up so you can launch ResInsight easily, whether that is a command you type, a desktop icon, or both.

A detail worth knowing about upfront: ResInsight's downloadable files are not the same for every release. Some older releases only had a Windows version available. Newer releases added macOS, then a build for RHEL-based Linux distributions, then separate builds for Ubuntu depending on which compiler was used to build them. Because this keeps changing release to release, the installer does not guess a file name. It always asks GitHub what is actually available for the specific version you are installing, then works out which one applies to your computer. If a release genuinely has nothing for your platform, it will tell you clearly rather than downloading the wrong thing.

### ResInsight on Linux and macOS

This section covers `resinsight-setup.sh`.

#### Step 1: Open a terminal

Same as the OPM Flow section above: `Ctrl + Alt + T` on most Linux desktops, or `Cmd + Space` then type `Terminal` on macOS.

#### Step 2: Go to the folder where you saved the script

```bash
cd ~/Downloads
```

adjusting the folder name if you saved it somewhere else.

#### Step 3: Make the script executable

```bash
chmod +x resinsight-setup.sh
```

#### Step 4: Run the script

```bash
sudo ./resinsight-setup.sh
```

By default this installs ResInsight system-wide (into `/opt/resinsight` on Linux, or `/Applications` on macOS), and adds a `resinsight` command to `/usr/local/bin` so anyone using your computer can run it. That is why `sudo` is needed.

**If you would rather not use `sudo` at all**, you can install into a folder you already own instead, for example your own home folder:

```bash
./resinsight-setup.sh --install-root "$HOME/resinsight"
```

Run without `sudo` this way, the script will not need administrator rights for the main install. Note that it may still ask for your password for one specific reason, explained in the note just below.

**A note on why you might still get asked for a password even without `sudo`:** if you run the script normally (not through `sudo`) but your account does not have write access to the default install folder or `/usr/local/bin`, the script will ask for your password at exactly that point, using `sudo` internally just for that one step. This is intentional, it means you only get a password prompt when it is actually necessary, rather than being forced to prefix the entire command with `sudo` up front. If you use `--install-root` with a folder you already own, as shown above, this will not happen at all.

**What can go wrong here:**

- **"Permission denied" when trying to create `/opt/resinsight`**: this means you ran the script without `sudo` and your account cannot write to `/opt`. Either re-run with `sudo ./resinsight-setup.sh`, or use `--install-root` as shown above to install somewhere you already own.
- **`sudo: ./resinsight-setup.sh: command not found`**: you skipped Step 3. Run `chmod +x resinsight-setup.sh` first.
- **A password prompt appears more than once during the same run**: this is normal if multiple separate steps each need elevated access (for example, creating the install folder and then also creating the command shortcut). Just type your password again when asked.

#### Step 5: Linux specific, picking a build if you are on Ubuntu

Some ResInsight releases publish two different Ubuntu builds, one built with a compiler called `gcc` and one built with `clang`. Unless you have a specific reason to prefer one, the script defaults to `gcc`, which is the more common choice. If you do want the other one:

```bash
./resinsight-setup.sh --toolchain clang
```

This only matters on Ubuntu and Debian-based systems. On RHEL-based systems (Fedora, Rocky Linux, AlmaLinux, and similar) and on macOS, this option is simply ignored, since there is only one build available for those.

#### Step 6: Watch it download, unpack, and install

You will see log lines about resolving the release, selecting a file, downloading, and installing. This can take a little while, since ResInsight's download is fairly large (upwards of 70 to 130 megabytes depending on your platform).

Downloaded files are kept in a small cache folder (`~/.cache/resinsight-setup` on Linux, `~/Library/Caches/resinsight-setup` on macOS), so if you ever reinstall the same version, or point the installer at a different folder with `--install-root`, it reuses the already-downloaded file instead of fetching it from the internet again.

**What can go wrong here:**

- **"Release has no asset for this platform"**: the specific version you asked for genuinely does not have a build for your operating system. The script will show you exactly which files that release does have. Try a newer version, or check the release page on GitHub yourself to see what is available.
- **A message about a GitHub API rate limit**: GitHub limits how many requests an unauthenticated computer can make in a short time window. This is rare for a single install, but can happen if you run the script many times in quick succession while testing something. Wait a while and try again.

#### Step 7: Running ResInsight

Once installed, you can launch it by typing:

```bash
resinsight
```

from any terminal window, on any operating system this script supports. On Linux, the installer also adds a ResInsight entry to your applications menu, complete with ResInsight's own icon, the same place you would find any other installed app, so you can launch it by clicking rather than typing a command if you prefer.

On macOS, since ResInsight installs as a normal `.app` bundle into your Applications folder, it already shows up in Launchpad and Spotlight automatically. No extra step is needed for that.

**What can go wrong here:**

- **"Permission denied" when running `resinsight`**: if this happens after a successful install, it usually means a file permission issue from an older version of this installer. Re-run the installer once (it is safe to run again) to have it recreate the command with the correct permissions, then try again.
- **On macOS, "app is damaged and can't be opened"**: this happens because ResInsight's current macOS build is not digitally signed by Apple, which macOS treats with extra suspicion by default (this is called Gatekeeper). The installer already handles this for you automatically during install by removing the quarantine flag Apple attaches to newly downloaded files. If you still see this message, it likely means the file was downloaded or moved some other way after the installer ran. Re-running the installer will fix it.
- **On Linux, the application menu entry shows a blank or generic icon**: the installer looks for an icon bundled inside that specific ResInsight release first, and downloads a known-good copy of ResInsight's own icon as a backup if it cannot find one, so this should be uncommon. If you still see a blank icon, it is most likely because your computer could not reach the internet to download that backup icon at install time (for example, no connection, or a restricted network). It is purely cosmetic either way; the program itself works exactly the same. Re-running the installer once you have a working internet connection will fix it. Some desktop environments also only refresh their icon cache when you log out and back in, so try that too if a re-run does not seem to help right away.

### ResInsight on Windows

This section covers `resinsight-setup.ps1`.

#### Step 1: Open PowerShell

Open the Start menu, type `PowerShell`, and open it normally. Administrator rights are not required for this script.

#### Step 2: Go to the folder where you saved the script

```powershell
cd $HOME\Downloads
```

#### Step 3: Allow the script to run

Same reasoning as the OPM Flow Windows section above, Windows blocks scripts by default:

```powershell
powershell -ExecutionPolicy Bypass -File .\resinsight-setup.ps1
```

#### Step 4: Watch it download and install

The script installs ResInsight into a folder under `$env:LOCALAPPDATA`, and by default creates a shortcut for it in your Start Menu automatically, so you can find and launch it the normal Windows way, by searching for it in the Start Menu.

If you would also like a shortcut on your Desktop, add this flag:

```powershell
.\resinsight-setup.ps1 -DesktopShortcut
```

If you would rather skip shortcut creation entirely:

```powershell
.\resinsight-setup.ps1 -NoShortcut
```

If you would like the `resinsight` command itself available in PowerShell (in addition to the Start Menu shortcut), add:

```powershell
.\resinsight-setup.ps1 -AddToPath
```

You can combine flags, for example `.\resinsight-setup.ps1 -AddToPath -DesktopShortcut`.

**What can go wrong here:**

- **"cannot be loaded because running scripts is disabled on this system"**: same execution policy protection covered in the OPM Flow Windows section. Use the command in Step 3 above.
- **You ran with `-AddToPath` but typing `resinsight` still is not recognized**: close your PowerShell window and open a new one. PATH changes only apply to newly opened windows, not the one you were already using.
- **"Release has no Windows asset"**: the version you requested does not have a Windows build. This is uncommon since Windows was the very first platform ResInsight supported, but if you are pinning an unusual or very new version, try `latest` instead, or check the release page yourself.

#### Step 5: Running ResInsight

Either search for **ResInsight** in your Start Menu and click it, or, if you used `-AddToPath`, type:

```powershell
resinsight
```

from any PowerShell window.

### How the ResInsight installer works, for the curious

ResInsight ships its Linux builds with a small launcher script alongside the real program, meant to set a few things up before starting the actual application. That launcher script works out where it is located using an older, somewhat fragile shell technique that does not reliably work when you try to run it from a shortcut or from a different folder than the one it lives in. Rather than relying on that, our installer works out the real, correct location of the ResInsight program at install time and writes its own small, more reliable launcher pointing directly at it. This is why running `resinsight` works correctly from anywhere on your computer, not just from inside ResInsight's own install folder.

On Windows, no such workaround is needed. Windows programs find their own supporting files based on where the actual program file is, regardless of how you launched it, so the installer simply points a shortcut and an optional PATH entry straight at the real program.

## Part 3: Uninstalling

Every installer in this guide has a matching uninstaller. They are separate scripts, so you only download them if you actually need them.

### Before you uninstall

A few things are worth knowing before you remove anything.

**You may not need to uninstall at all.** If your goal is to switch to a different OPM Flow version, you do not have to remove anything first. See [How do I switch to a different OPM Flow version later?](FAQ.md#how-do-i-switch-to-a-different-opm-flow-version-later). Uninstalling is for when you no longer want the tool, want your disk space back, or want a completely clean start.

**Your own work is safe.** The uninstallers only remove what the installers put on your computer. They never touch your simulation files (`.DATA` files and results) or your ResInsight project files.

**Docker and WSL2 are left alone.** The OPM Flow installer may have installed Docker for you, but Docker is a big, general purpose tool that many people use for other things too. The installer does not keep a record of whether it was the one that installed Docker, so the uninstaller cannot know whether removing it would break something else you rely on. It never removes Docker for you. If you want Docker gone as well, see [Removing Docker and WSL2 yourself](#removing-docker-and-wsl2-yourself-optional).

**Every uninstaller shows you what it found before it removes anything, and asks you first.** You will always get a chance to say no.

### What gets removed, and what never does

| | OPM Flow | ResInsight |
|---|---|---|
| **Removed** | The `opmflow` and `flow` commands, the saved settings, and the OPM Flow Docker images that were downloaded | The program, its commands and menu entries or shortcuts, any PATH entries it added, and the download cache |
| **Never removed** | Docker, Docker Desktop, WSL2, and your simulation files | Your ResInsight project files and ResInsight's own saved preferences (for example its list of recent files) |

### Getting the uninstall scripts

Getting them works exactly like getting the setup scripts, so if you need a refresher, see [Getting the scripts onto your computer](#getting-the-scripts-onto-your-computer). The four uninstall scripts are:

| Script | What it removes | Platform |
|---|---|---|
| `opmflow-uninstall.sh` | OPM Flow | Linux and macOS |
| `opmflow-uninstall.ps1` | OPM Flow | Windows |
| `resinsight-uninstall.sh` | ResInsight | Linux and macOS |
| `resinsight-uninstall.ps1` | ResInsight | Windows |

For example, to download the Linux and macOS one for OPM Flow from a terminal:

```bash
curl -O https://raw.githubusercontent.com/ti-oluwa/opmflow-setup-guide/refs/heads/main/scripts/opmflow-uninstall.sh
```

Or the Windows one for ResInsight, in PowerShell:

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/ti-oluwa/opmflow-setup-guide/refs/heads/main/scripts/resinsight-uninstall.ps1 -OutFile resinsight-uninstall.ps1
```

Just swap the file name at the end for whichever script you need. The same warning from before applies: if your browser saves the file as `something.sh.txt`, rename it so it ends in `.sh` or `.ps1`.

Because an uninstaller deletes things, the [security disclaimer](#security-disclaimer-please-read-this-first) near the top applies to these scripts just as much as to the installers, and the preview described next is the best way to build confidence before you run one for real.

### Preview first with a dry run

Every uninstall script has a **dry run** mode. A dry run shows you exactly what the script found and what it would remove, and then stops without changing anything at all. It is the safest way to find out what an uninstaller will do on your own computer, so we recommend always doing it first.

- On Linux and macOS, add `--dry-run` after the script name.
- On Windows, add `-DryRun` after the script name.

You will see this used in every walkthrough below. A dry run does not need `sudo` on Linux and macOS.

When you run an uninstaller for real, it ends by asking:

```
Remove the items marked 'remove' above? [y/N]
```

The capital **N** means "no" is the default, so if you just press Enter, nothing happens. Type `y` and press Enter to go ahead. Every list the script prints marks each item as `remove` (it will be deleted), `keep` (it was found, but it is deliberately being left alone, and the line tells you why) or `skip` (something could not be checked, and the line tells you why).

### Uninstalling OPM Flow on Linux and macOS

This section covers `opmflow-uninstall.sh`.

#### Step 1: Open a terminal and go to the script

Open a terminal and go to the folder where you saved the script, exactly as in [OPM Flow on Linux and macOS](#opm-flow-on-linux-and-macos), Steps 1 and 2. For example:

```bash
cd ~/Downloads
```

#### Step 2: Make the script executable

```bash
chmod +x opmflow-uninstall.sh
```

As before, nothing will appear to happen. That is normal.

#### Step 3: Preview what it would remove

```bash
./opmflow-uninstall.sh --dry-run
```

You will see something like this:

```
[opm-flow] Found on this computer:
[opm-flow]
[opm-flow]     remove    /usr/local/bin/opmflow   (the OPM Flow command)
[opm-flow]     remove    /usr/local/bin/flow   (shortcut to the command above)
[opm-flow]     remove    /etc/opm-flow   (saved version and variant settings)
[opm-flow]     remove    Docker image openporousmedia/opmreleases:2026.04_amd64
[opm-flow]
[opm-flow] Not touched, on purpose:
[opm-flow]     - Docker itself
[opm-flow]     - your simulation files (.DATA files and results)
```

If the list looks right, continue.

#### Step 4: Run it for real

```bash
sudo ./opmflow-uninstall.sh
```

Enter your password if asked, read the list one more time, and type `y` to confirm. We need `sudo` here for the same reason the installer did: the `opmflow` and `flow` commands and their settings live in system folders.

If you would like to remove the commands but keep the downloaded Docker images, so that a later reinstall is much faster, add `--keep-images`:

```bash
sudo ./opmflow-uninstall.sh --keep-images
```

The images are usually the biggest part of an OPM Flow installation, so if you are uninstalling to free up disk space, do not use this option.

#### Step 5: Check that it worked

Open a **new** terminal window and type:

```bash
flow --help
```

You should now see `command not found`. If you want to double check that the images are gone as well, type:

```bash
docker image ls openporousmedia/opmreleases
```

You should see an empty table with just the column titles.

**What can go wrong here:**

- **"This uninstaller must be run with sudo"**: you ran it without `sudo` and without `--dry-run`. Use the command in Step 4.
- **"Docker is installed but not running"** (shown as a `skip` line): the script cannot remove Docker images while Docker is switched off, and it deliberately never starts Docker for you. The commands and settings were still removed. Start Docker (on macOS, open Docker Desktop and wait for the whale icon to settle), then simply run the uninstaller again. It is safe to run it as many times as you like, and the second run will pick up the images.
- **"Docker refused to remove it (is a simulation still running?)"**: Docker will not delete an image while a container is still using it, and the script never forces it. Wait for your simulation to finish, or stop it, then run the uninstaller again.
- **A line saying `/usr/local/bin/flow` was left alone because it is "not the OPM Flow command"**: `flow` is a common name, and other programs use it too (a well known JavaScript tool is also called `flow`, for example). The uninstaller only deletes a `flow` that points at the OPM Flow command, and leaves anything else untouched. One honest gotcha here: if you already had a different `flow` before you installed OPM Flow, the installer replaced it, and the uninstaller has no way to bring it back. You would have to reinstall that other program.
- **`flow` still seems to work in the same terminal window after uninstalling**: your terminal remembers where commands were. Run `hash -r`, or just open a new terminal window.
- **"Cannot ask for confirmation because there is no terminal"**: this only happens if the script was started somewhere that cannot show a question, such as an automated job. Add `--yes` to go ahead without being asked.
- **On macOS, the Docker images are listed as skipped even though you installed OPM Flow**: make sure Docker Desktop is open and fully running (the whale icon in the menu bar should have stopped animating), then run the uninstaller again.

### Uninstalling OPM Flow on Windows

This section covers `opmflow-uninstall.ps1`. You do **not** need an Administrator PowerShell for this one, because everything the installer put there lives inside your own user folder.

#### Step 1: Open PowerShell and go to the script

Open PowerShell normally and go to the folder where you saved the script, as in [OPM Flow on Windows](#opm-flow-on-windows). For example:

```powershell
cd $HOME\Downloads
```

#### Step 2: Preview what it would remove

As with the installer, Windows blocks scripts by default, so we run it with a one-off permission:

```powershell
powershell -ExecutionPolicy Bypass -File .\opmflow-uninstall.ps1 -DryRun
```

#### Step 3: Run it for real

```powershell
powershell -ExecutionPolicy Bypass -File .\opmflow-uninstall.ps1
```

Read the list, then type `y` and press Enter. To keep the downloaded Docker images and only remove the commands and settings, add `-KeepImages` at the end.

#### Step 4: Check that it worked

Close PowerShell, open a **new** PowerShell window, and type:

```powershell
flow
```

You should see that `flow` is not recognized as a command.

**What can go wrong here:**

- **"Docker Desktop is installed but not running"** (shown as a `skip` line): same as on Linux and macOS. The commands and settings are removed, but the images cannot be removed while Docker Desktop is switched off, and the script never starts it for you. Open Docker Desktop, wait until it says it is running, and run the uninstaller again.
- **`flow` still works in a PowerShell window that was already open**: that is expected. Windows only reads your PATH when a window opens, so windows that were already open keep their old copy until you close and reopen them. The script clears it from the window you ran it in.
- **A warning that your PATH could not be updated**: the commands themselves were still removed, so nothing is broken, but a leftover entry may remain in your PATH. It is harmless, but you can remove it by hand: press the Windows key, search for **Edit environment variables for your account**, select **Path**, click **Edit**, select the line ending in `opm-flow\bin`, click **Delete**, and then **OK** on each window.
- **"I want my old PATH back"**: before changing your PATH, the script saves your previous PATH to a small text file in your temporary folder, named like `opmflow-uninstall-user-path-20261005-101500.txt`, and tells you where. You can open your temporary folder by pressing the Windows key plus `R`, typing `%TEMP%`, and pressing Enter. Windows clears this folder out from time to time, so do not rely on it for the long term.
- **You installed from a different Windows account**: if you installed while signed in as a different user (for example a separate administrator account), the files are inside that account's user folder, not yours. Sign in as that account to uninstall.

### Uninstalling ResInsight on Linux and macOS

This section covers `resinsight-uninstall.sh`.

#### Step 1: Open a terminal, go to the script and make it executable

As in [ResInsight on Linux and macOS](#resinsight-on-linux-and-macos), Steps 1 to 3:

```bash
cd ~/Downloads
chmod +x resinsight-uninstall.sh
```

#### Step 2: Close ResInsight

If ResInsight is open, close it completely first. The uninstaller will stop and ask you to do this if it finds ResInsight running, rather than deleting files out from under a running program.

#### Step 3: Preview what it would remove

```bash
./resinsight-uninstall.sh --dry-run
```

On Linux, you will see something like this (the exact versions and folders will match your own computer):

```
[resinsight] Looking in: /opt/resinsight
[resinsight]
[resinsight] Found on this computer:
[resinsight]
[resinsight]     remove    /opt/resinsight/v2026.06.1   (ResInsight v2026.06.1, 412M)
[resinsight]     remove    /usr/local/bin/resinsight   (the 'resinsight' command)
[resinsight]     remove    /home/you/.local/share/applications/resinsight.desktop   (application menu entry)
[resinsight]     remove    /root/.cache/resinsight-setup/v2026.06.1   (downloaded installer files, 185M)
```

#### Step 4: Run it for real

If you installed ResInsight with `sudo` (the default on Linux), uninstall with `sudo` too:

```bash
sudo ./resinsight-uninstall.sh
```

If you installed into a folder of your own with `--install-root` (see below), you do not need `sudo`. The script also asks for your password itself, only at the moment it needs one.

Type `y` to confirm.

#### Step 5: Check that it worked

Open a new terminal and type `resinsight`. You should see `command not found`. On Linux, ResInsight should also have disappeared from your applications menu. On some desktops this takes a moment, or until you log out and back in.

#### Options you may need

| Option | What it does |
|---|---|
| `--dry-run` | Show what would be removed, and change nothing |
| `--version 2026.06.0` | Remove only that version. The leading `v` is optional |
| `--install-root FOLDER` | Where ResInsight was installed, if you gave the installer a custom `--install-root` |
| `--keep-cache` | Keep the downloaded installer files, so a later reinstall does not need to download them again |
| `--yes` | Do not ask for confirmation |

**What can go wrong here:**

- **"ResInsight is running right now"**: close ResInsight completely (on macOS, quit it from the menu bar, not just close the window) and run the uninstaller again.
- **"Nothing to remove", but you know ResInsight is installed**: you most likely gave the installer a custom `--install-root`. The installer does not remember where it installed, so tell the uninstaller the same folder. The script helps here: if the `resinsight` command points somewhere else, it prints that location for you. For example:

  ```bash
  ./resinsight-uninstall.sh --install-root "$HOME/resinsight"
  ```

  Keep the quotes, and use `$HOME` rather than `~` inside them, because `~` is not expanded inside quotes or after an `=` sign.
- **You have more than one version installed, and only want to remove one**: the installer keeps each version in its own folder, so use `--version`. A `resinsight` command or shortcut that still points at a version you are keeping is left in place and keeps working. If you remove the specific version that the `resinsight` command pointed at, the command goes with it, and the script tells you how to get it back for the version that remains (run the installer again for that version).
- **On macOS, the script says `ResInsight.app` "was not installed by this installer" and leaves it**: the installer leaves a small version marker file next to the app it installs, and the uninstaller only removes an app that has one. That protects a copy of ResInsight you installed some other way. If you do want that copy gone, drag it to the Trash yourself.
- **A line saying a command or menu entry was left alone because it was "not created by the ResInsight installer"**: the uninstaller only deletes files it can positively recognize as its own. Anything else with a similar name is left untouched and reported to you.
- **Two different "cache" locations**: if you installed with `sudo`, the downloaded installer files are usually stored in the administrator's home folder, while the menu icon is stored in your own. The uninstaller checks both, which is another reason to run it with `sudo` if you installed with `sudo`.
- **Some empty folders such as `~/.cache` are left behind**: those are standard folders that many programs share, so the uninstaller never removes them, even when they happen to be empty.

### Uninstalling ResInsight on Windows

This section covers `resinsight-uninstall.ps1`. As with the installer, no Administrator rights are needed.

#### Step 1: Close ResInsight, open PowerShell and go to the script

Close ResInsight completely if it is open, then:

```powershell
cd $HOME\Downloads
```

#### Step 2: Preview what it would remove

```powershell
powershell -ExecutionPolicy Bypass -File .\resinsight-uninstall.ps1 -DryRun
```

#### Step 3: Run it for real

```powershell
powershell -ExecutionPolicy Bypass -File .\resinsight-uninstall.ps1
```

Read the list, then type `y` and press Enter.

#### Step 4: Check that it worked

Press the Windows key and search for **ResInsight**. It should no longer appear. If you used `-AddToPath` when installing, open a new PowerShell window and type `resinsight` to confirm the command is gone.

#### Options you may need

| Option | What it does |
|---|---|
| `-DryRun` | Show what would be removed, and change nothing |
| `-Version 2026.06.0` | Remove only that version. The leading `v` is optional |
| `-InstallRoot "D:\Tools\ResInsight"` | Where ResInsight was installed, if you gave the installer a custom `-InstallRoot` |
| `-KeepCache` | Keep the downloaded installer files, so a later reinstall does not need to download them again |
| `-Yes` | Do not ask for confirmation |

Add these at the end of the command, for example:

```powershell
powershell -ExecutionPolicy Bypass -File .\resinsight-uninstall.ps1 -Version 2026.06.0 -DryRun
```

**What can go wrong here:**

- **"ResInsight is running right now"**: close ResInsight completely and run the uninstaller again.
- **"Could not fully remove" a folder**: Windows refuses to delete files that something else has open. The usual culprits are ResInsight itself, a File Explorer window that is showing that folder, or an antivirus scan that is busy with it. Close those and run the uninstaller again. It is safe to repeat, and the script picks up where it left off.
- **A shortcut was left in place with a note that it points at another version**: this is deliberate. When you have more than one version installed and remove only one, any shortcut that still points at a version you are keeping is left alone, so it keeps working. If you remove the version a shortcut pointed at, the shortcut is removed, and the script tells you how to recreate it for the version that remains (run the installer again for that version).
- **"Nothing to remove", but you know ResInsight is installed**: you most likely gave the installer a custom `-InstallRoot`. Give the same folder to the uninstaller. If a shortcut points at ResInsight somewhere else, the script prints that location for you.
- **PATH entries**: these only exist if you installed with `-AddToPath`. If you installed several versions with it, there may be one entry for each, including ones for versions you had already deleted by hand. When you remove everything, the uninstaller removes those leftovers too. Every other entry in your PATH is kept exactly as it was, and a backup of your previous PATH is saved to your temporary folder first. See the OPM Flow Windows section above for how to find it, and for how to edit your PATH by hand if the script ever warns that it could not.
- **Your Desktop shortcut is not found**: if your Desktop is synced with OneDrive, Windows keeps it in a different place. The script asks Windows for the real location, so it normally finds it anyway. If it ever misses one, you can simply delete that shortcut yourself.

### Removing Docker and WSL2 yourself (optional)

Only do this part if you are sure you no longer need Docker for anything else. It is not part of the uninstall scripts, on purpose.

**Be careful, because this can delete other people's work too.** Docker keeps every image, container and volume you have ever created in one place, and removing Docker Desktop removes all of it, not just the OPM Flow parts. Before going ahead, check what else you have:

```bash
docker ps -a
docker image ls
docker volume ls
```

If any of that is something you care about, back it up first, or leave Docker installed. Leaving Docker installed costs you nothing except some disk space.

If you are sure:

- **Docker Desktop (Windows and macOS):** follow Docker's own instructions at [docs.docker.com/desktop/uninstall](https://docs.docker.com/desktop/uninstall/). On Windows this is also available by opening **Settings**, then **Apps**, finding **Docker Desktop**, and choosing **Uninstall**.
- **Docker on Linux:** the exact steps depend on your distribution, and on whether you installed Docker Engine or Docker Desktop. Docker's installation pages for each distribution, at [docs.docker.com/engine/install](https://docs.docker.com/engine/install/), include an "uninstall" section that is specific to yours.
- **WSL2 (Windows only):** WSL2 may be in use for other Linux systems that you installed, and removing a Linux system from WSL permanently deletes every file inside it. Do not remove WSL2 unless you are completely sure nothing else on the computer uses it. If you are sure, you can turn the feature off from **Turn Windows features on or off** in the Start menu.

### How the uninstallers keep your computer safe, for the curious

If you are happy just using the tools, you can skip this part. If you want to know why we are comfortable asking you to run scripts that delete things, here is how they are built.

- **They identify before they delete.** Nothing is removed with a broad pattern or a wildcard. Every deletion is of one specific path that was recognized first, and every one of them is shown to you before you are asked to confirm.
- **They only remove what they can prove is theirs.** The installers leave recognizable fingerprints behind: a particular piece of text inside the `opmflow` command, a small `.installed-version` marker file next to every ResInsight version, and a link that points at one exact place. The uninstallers look for those. A `flow` command that points somewhere else, a ResInsight folder with no marker, or a shortcut that points at a different install is left alone and reported, instead of being deleted because its name looked right.
- **They never remove a whole folder blindly.** Folders such as the OPM Flow settings folder are only removed if they are empty after the script's own files are gone. If you put something else in there, it stays.
- **They never force anything.** Docker images that are in use are reported, not forced out. Files that are in use on Windows are reported, not skipped silently.
- **They never start or install anything.** If Docker is not running, the script tells you rather than launching it. And an uninstaller never installs anything.
- **Docker and WSL2 are never touched.** See above for why.
- **On Windows, your PATH is edited with great care.** Only the exact entries added by the installers are removed. Every other entry is kept character for character, including ones that use `%VARIABLES%`, and a backup of your previous PATH is saved first. The common shortcut for editing PATH silently rewrites entries that have nothing to do with what you are doing, so the script avoids it.
- **Removing one thing never breaks another.** With several ResInsight versions installed, a command, shortcut or menu entry that still points at a version you are keeping is not removed.
- **A dry run is always available**, and so is a confirmation question that defaults to "no".
- **Running them twice is fine.** Each part of an uninstall is checked separately, so if something could not be removed the first time (Docker was switched off, a file was in use), running the uninstaller again picks up what is left, and running it when everything is already gone just says so.

## Frequently asked questions

We have collected a separate list of common questions and answers in [FAQ.md](FAQ.md). If something is confusing or was not covered clearly enough in this guide, check there before reaching out, there is a good chance someone else has already asked the same thing.

## Reporting a problem

If you run into an error that this guide did not help you solve, please open an issue rather than suffering in silence. Detailed instructions and a template for exactly what to include are in [ISSUE.md](ISSUE.md). The short version: tell us your operating system, which script you ran, the exact command you typed, and paste the full error text you saw. The more detail you give, the faster we can actually fix it.

## Contributing

If you would like to help improve these scripts or this documentation, see [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started.

## One last reminder

Please reread the [security disclaimer](#security-disclaimer-please-read-this-first) near the top of this document before running anything with administrator rights. We have done our best to make sure these scripts are safe, but you should always feel free to read through a script yourself before running it, especially with elevated permissions.
