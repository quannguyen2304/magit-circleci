# magit-circleci

Magit extension for CircleCI. This project based on the https://github.com/abrochard/magit-circleci and refactor to use CircleCI v2. It support to get the info of the latest commit and approve the workflow.

## Setup
---
1. Get your token in CircleCI (refer https://circleci.com/docs/api/#add-an-api-token).
2. Load the magit-circleci package and add the CircleCI token, CircleCI organisation name in the config
```
(load! "magit-circleci")
(setq magit-circleci-token "XXXXXXXX")
(setq magit-circleci-organisation-name "")
```

## Usage
---

In the Magit status

```
M-x magit-circleci-mode : to activate.
M-x magit-circleci-pull : to get the latest commit.
" : in magit status to open the CircleCI Menu.
" f : to pull latest builds for the current repo.
C-c C-a: to approve the workflow (apply with the Waitting for approve title).
```

## Customization
---
 - The extension need to have the CIRCLECI_ORGANISATION_NAME value, 