# Contributing

Edit this checkout. Omarchy loads a copy, and it rejects symlinks inside a plugin folder.

```bash
rsync -a --delete --exclude .git \
  ~/src/omarchy-appimages/ \
  ~/.config/omarchy/plugins/07dcolem.appimages/
omarchy plugin validate ~/.config/omarchy/plugins/07dcolem.appimages
```

Saving a file under `~/.config/omarchy/plugins/` reloads plugin code. If the bar does not pick up a change, run `omarchy restart shell`.

Tests use a throwaway `HOME` and do not touch the real `~/Applications` or desktop files:

```bash
make test
```

Bash house style, the URL install rules, and a manual verification checklist are in [docs/development.md](docs/development.md).

There is no `origin` remote yet. Do not publish with `gh repo create`. That would be a disconnected repository. When publishing is requested, fork the upstream project so GitHub keeps the fork relationship, then push this branch:

```bash
gh repo fork kabe2007/omarchy-appimage-integration \
  --clone=false --remote=false --fork-name omarchy-appimages
git remote add origin git@github.com:07dcolem/omarchy-appimages.git
git push -u origin plugin-v0.1
```

`--fork-name` still records `07dcolem/omarchy-appimages` as a fork of `kabe2007/omarchy-appimage-integration`. The local `upstream` remote already points there, so do not let `gh repo fork` add or rename remotes.

Keep `LICENSE`, `NOTICE`, and the README attribution block. Juan I. de Elizalde stays first on the copyright lines.
