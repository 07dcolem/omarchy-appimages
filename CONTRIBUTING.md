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

There is no `origin` remote yet. A later publish, only when asked, is:

```bash
git remote add origin git@github.com:07dcolem/omarchy-appimages.git
# then, only when the human says so: gh repo create / git push -u origin plugin-v0.1
```
