# Skills Registry

This repository is the top-level registry for reusable skills.

Each skill should live under `skills/<skill-name>` as its own Git repository,
added to this repository as a Git submodule. That keeps every skill independently
versioned and pushable while this repository records which skill revisions are
currently selected.

## Add a Skill

```bash
git submodule add <skill-repo-url> skills/<skill-name>
git add .gitmodules skills/<skill-name>
git commit -m "Add <skill-name> skill"
git push
```

## Update a Skill

```bash
cd skills/<skill-name>
git pull
# or edit, commit, and push changes inside the skill repo

cd ../..
git add skills/<skill-name>
git commit -m "Update <skill-name> skill pointer"
git push
```

## Clone With Skills

```bash
git clone --recurse-submodules https://github.com/Program120/skills.git
```

If the repository was already cloned:

```bash
git submodule update --init --recursive
```

