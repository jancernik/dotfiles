# dotfiles

<sub>The never-ending dotfiles...</sub>

This repo contains most of the config and scripts I use on my current machine.
It's meant as a fresh start, created right after my latest Linux install, and aims to be my dream custom, clean, tidy, and long-lasting workstation setup.

I don't have all the config just yet, but the idea is to include as much as possible for my own organization, and to make it easy when I eventually recreate and sync everything with my laptop.

Currently quite simple, but perfectly functional for my workflow.

### My setup

- Arch Linux
- Full Disk Encryption with LUKS
- BTRFS with @ and @home subvolumes
- Automatic Timeshift Snapshots and GRUB entries for recovery
- Hyprland

## Still in the works

### Windows 11 VM with AMD Raphael iGPU passthrough

Adobe... it's still one of the reasons I can't leave Windows behind completely.
For most of the products I used (Photoshop, Illustrator, Premiere), I've found alternatives, but Lightroom is still my Achilles' heel.

I tried Darktable briefly, but the workflow is quite different from what I'm used to, and for the things I do, investing time into learning it isn't really an option right now, although I'm sure I'll end up doing that at some point.
I don't use the Adobe suite that often, but when I do, it's always a pain having to dual boot, deal with Windows updates, etc.

So what if...

Since I use an NVIDIA graphics card as my main one, I could have a Windows VM that I pass my unused integrated GPU to. That GPU is plenty powerful for what I'll be doing, and in theory, I should get close to native performance.

Many people advise against it since it's pretty tricky stuff, but still, the success stories lured me in anyway. Sadly, I tried for several days to do it myself, but for the life of me I couldn't get it working. I always ended up with the famous Code 43.
So for now, I'm letting that rest, and I'll try again when I have more time.
