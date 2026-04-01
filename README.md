# dotfiles

<sub>The never-ending dotfiles...</sub>

This repo has most of the config and scripts I use across my main machines. It started as a clean restart after a fresh install, but at this point it's basically the shared setup for both my desktop and laptop.

Everything is managed with [chezmoi](https://www.chezmoi.io/), and some parts use templates so both machines can share the same dotfiles without needing the exact same config everywhere.

It's mostly here for my own organization, to make rebuilding a machine less annoying, and to keep the whole setup consistent between both systems.

---

## Current setup

- Arch Linux
- Full disk encryption with LUKS
- BTRFS with `@` and `@home` subvolumes
- Automatic Timeshift snapshots with GRUB entries for recovery
- Hyprland
- My custom WIP desktop shell [minishell](https://github.com/jancernik/minishell)

## Apply with chezmoi

```bash
chezmoi init --apply --verbose https://github.com/jancernik/dotfiles.git
```
