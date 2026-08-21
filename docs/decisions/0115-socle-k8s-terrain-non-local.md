# 0115 — Socle k8s sur terrain non-`local` : brancher le moteur Python en prod

## Statut

Accepted (2026-08-20). Met en œuvre le volet « socle » du terrain
cloud/baremetal (cadré « cible, non implémenté » par
[ADR 0031](0031-terrain-cloud-arm.md) /
[ADR 0108](0108-isolation-par-identite-et-verbes-provision-install.md) §4) —
hors **provisioning IaC** (reste un stub,
[ADR 0032](0032-opentofu-provisioning-cloud.md)). L'implémentation test-driven
suit ([plan](../plans/plan-socle-non-local.md)).

## Contexte

`nestor next` / `nestor install` ne montaient le socle k8s (`bootstrap` : CRI +
kubeadm + Cilium) **qu'en terrain `local`** (banc Lima). Le câblage existant est
banc-seul :

- le callback `bootstrap()` du moteur `_run_path_engine` (`scripts/topology.py`)
  appelle `_runphases("inventory")` + `_runphases("facts")` →
  `bench/lima/run-phases.sh` (write_inventory Lima) + `limactl shell`
  (dérivation du `CP_IP` user-v2) — **sans branche `terrain`** ;
- `_monter_phase` (chemin `next`) exige, pour une phase sans play unitaire, un
  arm `run-phases.sh` (`_has_runphases_arm`). Or run-phases.sh n'a pas d'arm
  `bootstrap)` (il n'a que `cni)`/`facts)`/`inventory)`) → `next` propose
  `bootstrap` (1re phase du plan) mais **erre** (« ni play unitaire ni arm
  run-phases.sh — non lançable »).

Pourtant `next` est **censé monter la couche suivante sur tout terrain**
(lima/baremetal/cloud). Les **plays prod du socle existent**
(`bootstrap/cri.yaml`, `kubeadm.yaml`, `control-planes.yaml`,
`initialisation.yaml` + `cni.sh`, séquence RUNBOOK) et sont **terrain-agnostic**
(Ansible SSH + `cni.sh` pur installeur Cilium, vérifié : aucune réf limactl).
Mais ils n'étaient **pas câblés dans le moteur** pour un terrain non-`local`.
C'est l'angle-mort qu'on comble.

## Décision

**Brancher le montage du socle sur le `terrain` dans le moteur Python — le banc
reste sur son chemin éprouvé (run-phases.sh+limactl, inchangé), le prod emprunte
un chemin SSH qui réutilise les plays existants + `cni.sh`.**

1. **`bootstrap()` branché sur `terrain`.**
   - `local` → chemin actuel **inchangé**
     (`_runphases("inventory")`+`("facts")`+ `launch_socle`+`run_cni` via
     run-phases.sh+limactl) — banc vert conservé.
   - `cloud`/`baremetal` → chemin **prod** : on SAUTE `_runphases("inventory")`
     (l'inventaire est déjà dérivé par `_inventory_for` →
     `render_prod_inventory`, branche `terrain` existante) et
     `_runphases("facts")` (pas de limactl). Les plays du socle passent par
     `launch_socle` (Ansible, `ctx.inventory`) — **le même moule**, seul le
     transport change.

2. **`CP_IP` : `""` en prod** (kubeadm **auto-détecte** l'IP du nœud —
   `default(control_plane_ip, true)` dans
   [`bootstrap/roles/k8s-install/tasks/main.yaml`](../../bootstrap/roles/k8s-install/tasks/main.yaml),
   mono-CP). On ne dérive **PAS** d'IP en prod : pas de limactl, et l'inventaire
   dérivé ne porte pas `ansible_host` (le nœud est joignable par son **nom**
   résolu, DNS/`~/.ssh/config`, convention `hosts.example.yaml`).
   `bootstrap_extravars("")` → `{"control_plane_ip": ""}`.

3. **CNI prod : `cni.sh` sur le CP via SSH**
   (scp+`ssh debian@<cp> 'bash cni.sh'`), pas `_runphases("cni")` (banc).
   `cni.sh` est terrain-agnostic (installeur Cilium Helm+CLI+kubectl,
   idempotent). Le **rapatriement kubeconfig** (admin.conf du CP →
   `.kubeconfigs/<stack>.config`, endpoint réécrit, contexte estampillé
   `stack_id`) est fait **mid-run** après la CNI — réutilisation de la logique
   de `stack select`/`_select_prod_kubeconfig` (ADR 0108 §3), pour que les
   couches suivantes (qui kubectl) disposent du kubeconfig dans le même
   `nestor install`.

4. **`_monter_phase` route `bootstrap` vers le moteur** (au lieu d'errer) :
   `next` propose et monte le socle sur **tout terrain**. Fin de l'incohérence «
   propose une phase qu'on ne peut pas lancer ».

## Conséquences

- **Gain** : `nestor next`/`install` montent le socle k8s sur cloud/baremetal —
  `next` honore son contrat (tout terrain). Le socle-prod play-à-play du RUNBOOK
  devient un chemin automatisé (les plays+séquence restent la source humaine).
  Volet « socle » du terrain cloud comblé (le provisioning IaC reste un stub ADR
  0032).
- **Banc inchangé** : la branche `local` est strictement conservée — les tests
  existants (`test_plan`, `test_topology_cli`, bats) restent verts (garde-fou
  régression). La branche prod est testée en **unitaire** (logique de
  branchement `terrain → chemin`) ; le **flux réel** (SSH `cni.sh`, kubeadm
  auto-detect, rapatriement admin.conf) se révèle au **run sur le VPS** —
  validation finale par l'opérateur (inhérent à une 1re implémentation cloud).
- **Prix à payer** : un 2ᵉ chemin de socle (prod) à tenir à côté du banc — mais
  il réutilise les MÊMES plays + `cni.sh` + `launch_socle` (pas de duplication
  de la logique k8s, seul le transport diffère). Le rapatriement kubeconfig
  mid-run ajoute un couplage (CNI → kubeconfig → couches) à valider.
- **Limite assumée** : l'inventaire dérivé ne portant pas `ansible_host`, le
  nœud prod doit être **résolvable par son nom** (DNS / `~/.ssh.config`) —
  précondition déjà documentée (RUNBOOK, `hosts.example.yaml`). Lever le gap
  `ansible_host` non émis par le template `hosts.yaml.j2` est un **chantier
  séparé** (non requis ici : `control_plane_ip` vide le rend non-bloquant pour
  le socle).

## Alternatives écartées

- **Garder `next`/`install` banc-seuls + documenter le socle-prod play-à-play
  (RUNBOOK).** Écarté : `next` est **censé** monter la couche suivante sur tout
  terrain — c'est son contrat. Maintenir un chemin manuel prod à côté d'un
  chemin automatisé banc est une incohérence vécue (l'erreur « non lançable via
  next »).
- **Dériver le `CP_IP` de `ansible_host` du nœud** (exiger l'IP dans
  l'inventaire dérivé — fixer le template `hosts.yaml.j2`). Écarté :
  `control_plane_ip` est **optionnel** (kubeadm auto-détecte,
  `default(..., true)`) — pas besoin de porter l'IP dans l'inventaire pour le
  socle. L'émission d'`ansible_host` est un chantier à part (utile pour d'autres
  cas, pas requis ici).
- **Réécrire le socle en Python pur** (ne plus appeler run-phases.sh du tout).
  Écarté : ADR 0049/0097 — le bash garde les briques node-side irréductibles
  (limactl/CNI/inventaire). On réutilise `launch_socle`+`cni.sh` existants, on
  ne duplique pas la logique k8s.
