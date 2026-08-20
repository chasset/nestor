# 0115 — Retrait de la CI/CD GitHub-only : portage de la CI sur Gitea Actions

## Statut

Accepted (2026-08-20). Amende le volet « CI/CD d'usine » de la
[0112](0112-cicd-in-cluster-gitea-actions-buildkit.md) (Gitea Actions
in-cluster) en étendant la cible : **la CI/CD du dépôt nestor lui-même doit
tourner sur Gitea Actions**, pas seulement le build applicatif atlas. Retire les
workflows `.github/workflows/` dont les primitives sont 100 % GitHub-specific
(`codeql.yml`, `scorecard.yml`, `release.yml`, `resign-releases.yml`, le job
`deploy` de `docs.yml`) et rend les garde-fous restants **portables
GitHub/Gitea**.

## Contexte

Le dépôt nestor (ex `univ-lehavre/cluster`, repris par son mainteneur —
ADR 0023) est déployé dans le banc par une forge **Gitea** (air-gapped, ADR
0044), et sa chaîne applicative CI/CD est in-cluster Gitea Actions (ADR 0112).
Or la CI/CD du dépôt lui-même restait écrite **pour GitHub Actions uniquement**
:

- **CodeQL** (`codeql.yml`) — SAST uploadé sur l'onglet Security GitHub ; scopes
  `security-events`/`id-token` non supportés par Gitea ; exige GitHub Advanced
  Security sur dépôt privé (vérifié : le run échoue).
- **OpenSSF Scorecard** (`scorecard.yml`) — événement `branch_protection_rule`
  non supporté par Gitea, scopes `security-events`/`id-token`, badge/API GitHub,
  upload SARIF CodeQL.
- **Publication automatisée** (`release.yml`, `resign-releases.yml`) —
  release-please (PR + GitHub Release + tag), signature cosign **keyless OIDC**
  (l'`id-token` GitHub n'existe pas sur Gitea), générateur **SLSA**
  (`slsa-github-generator`, workflow réutilisable GitHub), CLI `gh release`.
- **Déploiement de la doc** (`docs.yml`, job `deploy`) — GitHub Pages
  (`deploy-pages`, scopes `pages` + `id-token`).
- **Ouverture d'issues de rappel** (`bench-freshness.yml`,
  `conventions-freshness.yml`) — CLI `gh` (label, issue, commentaire).

Gitea Actions (v1.26, ADR 0006) lit `.github/workflows/` **et**
`.gitea/workflows/`, supporte `push`/`pull_request`/`schedule`/
`workflow_dispatch`/`release`, le mot-clé `permissions:` (scopes réduits :
`contents`, `issues`, `pull-requests`, `actions`, `packages`…) et les actions
externalisées par `DEFAULT_ACTIONS_URL` — mais **pas** `branch_protection_rule`,
ni les scopes `security-events`/`id-token`/`pages`, ni GitHub Pages/Releases, ni
l'OIDC GitHub. La publication automatisée et le SAST GitHub n'ont **pas
d'équivalent Gitea** — les retirer, plutôt que les dupliquer.

## Décision

**La CI/CD du dépôt devient portable : elle tourne à l'identique sur GitHub
Actions et sur Gitea Actions.** Les panneaux 100 % GitHub sont **retirés**, pas
transposés :

- **Supprimés** : `codeql.yml`, `scorecard.yml`, `release.yml`,
  `resign-releases.yml`, ainsi que la config morte `release-please-config.json`
  - `.release-please-manifest.json` (consommés uniquement par `release.yml`).
- **`docs.yml`** : réduit au job `build` (validation `pnpm docs:build`, liens
  internes) ; le job `deploy` GitHub Pages et les scopes `pages`/`id-token`
  disparaissent.
- **`ci.yml`** : inchangé sauf deux gardes GitHub — le job `portability-macos`
  (runner macOS inexistant sur Gitea) et l'upload d'artefact du rapport gitleaks
  (Gitea ne stocke pas les artefacts) sont conditionnés par
  `env.GITHUB_SERVER_URL == 'https://github.com'` (variable posée par les deux
  forges).
- **`bench-freshness.yml` / `conventions-freshness.yml`** : l'ouverture d'issue
  est **double-forge** — `gh` sur `github.com`, API REST Gitea (curl + python3
  pour le JSON, token `GITEA_TOKEN`) sinon. Le dédoublonnage par label est
  conservé sur les deux forges.
- **Versionnement** : `main` reste gouverné par les Conventional Commits
  (commitlint) ; la version courante vit dans `package.json` + `CHANGELOG.md`
  (historique conservé, ADR 0023). La publication GitHub automatisée est
  supprimée — pas d'équivalent Gitea (pas de release-please Gitea).
- **Scorecard** : retiré. Le **Best Practices Badge** (état vérifié par
  l'OpenSSF, ADR 0080) reste, seul.

## Conséquences

- **Positif.** La CI tourne sur la forge réelle (Gitea in-cluster, air-gapped) :
  `push`/`pull_request` → lint, tests, scans et garde-fous, sans aucune
  primitive GitHub. Le code de CI est une seule source, pas deux copies
  (`.github/` vs `.gitea/`).
- **Négatif / limites.** Perte des alertes onglet Security GitHub (CodeQL,
  Scorecard SARIF) et de la publication automatisée des releases signées —
  acceptées : sans équivalent Gitea, elles resteraient du code mort sur la forge
  cible. Le job macOS et l'upload d'artefact ne tournent que sur GitHub. Gitea
  lit `.github/workflows/` comme `.gitea/workflows/` : le répertoire historique
  est conservé (aucun déplacement).
- **Docs vivantes mises à jour** : SAFEGUARDS.md, CONTRIBUTING.md, README.md
  (badges CodeQL/Scorecard/release retirés), bootstrap/RUNBOOK.md (vérification
  cosign/SLSA périmée). Les ADR (0080, 0087, 0088…) et audits restent des traces
  historiques — non réécrits (ADR 0023).

## Alternatives écartées

- **Dupliquer la CI dans `.gitea/workflows/`** : deux sources divergentes à
  maintenir ; Gitea lit déjà `.github/workflows/` — le répertoire n'est pas le
  problème, les primitives le sont.
- **Transposer CodeQL/Scorecard/release en équivalent Gitea** : il n'existe pas
  d'équivalent (pas de code scanning Gitea, pas de release-please, pas d'OIDC).
  Les garder = code mort ou portage partiel fragile.
- **Ne retirer que CodeQL/Scorecard** (les seuls en échec) : laissait la chaîne
  de release et le déploiement Pages GitHub, eux aussi inopérants sur Gitea —
  incohérent avec la cible « tourne sur la forge ».
