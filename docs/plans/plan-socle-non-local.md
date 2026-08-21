# Plan — Socle k8s sur terrain non-`local`

## État

> **État : Actif** (depuis 2026-08-20) · **Fonde :
> [ADR 0115](../decisions/0115-socle-k8s-terrain-non-local.md)** (Accepted) ·
> **Issues : _(à lier si des lots restent ouverts)_**.
>
> **Cadre**
> ([ADR 0057](../decisions/0057-gouvernance-documentaire-adr-plan-issue.md)) :
> ce plan met en œuvre
> l'[ADR 0115](../decisions/0115-socle-k8s-terrain-non-local.md) ; les
> _pourquoi_ vivent dans l'ADR, ce plan porte le déroulé.

## Objectif

Que `nestor next` / `nestor install` montent le socle k8s (`bootstrap` : CRI +
kubeadm + Cilium) sur **tout terrain** — y compris `cloud`/`baremetal`.
Aujourd'hui banc-seul (`bootstrap()` callback →
`bench/lima/run-phases.sh`+`limactl` ; `_monter_phase` erre sur `bootstrap`). On
branche le moteur sur le `terrain` : banc inchangé, prod via SSH réutilisant les
plays existants + `cni.sh`.

## Précondition

Le nœud prod est **résolvable par son nom** (DNS / `~/.ssh.config`) —
l'inventaire dérivé ne porte pas `ansible_host` (convention
`hosts.example.yaml`). Non bloquant pour le socle (`control_plane_ip=""` →
kubeadm auto-détecte).

## Lots

1. **ADR 0115** ✅ — décision enregistrée (ce plan la met en œuvre).
2. **`bootstrap()` callback branché `terrain`** (`scripts/topology.py`,
   `_run_path_engine`) :
   - `local` → chemin actuel **inchangé**
     (`_runphases("inventory")`+`("facts")`+ `launch_socle`+`run_cni` via
     run-phases.sh+limactl).
   - `cloud`/`baremetal` → sauter `_runphases("inventory")` (utilise
     `ctx.inventory` déjà dérivé par `_inventory_for`) et `_runphases("facts")`
     (pas de limactl) ; `cp_ip=""` (`bootstrap_extravars("")` → kubeadm
     auto-detect) ; plays via `launch_socle` (Ansible, `ctx.inventory`).
3. **CNI prod + kubeconfig mid-run** : `cni.sh` sur le CP via SSH
   (`scp`+`ssh debian@<cp> 'bash cni.sh'`) — terrain-agnostic. Rapatriement
   kubeconfig (admin.conf → `.kubeconfigs/<stack>.config`, endpoint réécrit,
   contexte estampillé `stack_id`) réutilisant la logique de
   `stack select`/`_select_prod_kubeconfig` — pour que les couches suivantes
   (kubectl) disposent du kubeconfig dans le même `nestor install`.
4. **`_monter_phase` route `bootstrap` vers le moteur** — `next` propose et
   monte le socle sur tout terrain (fin de l'erreur « non lançable via next »).
5. **Tests** (test-driven, banc vert) :
   - `tests/test_topology_cli.py` : `next`/`install` sur une topo `cloud` monte
     le socle via la **branche prod** (logique de branchement
     `terrain → chemin`), banc inchangé ;
   - `tests/test_plan.py` : la séquence de phases prod inclut `bootstrap` (déjà
     couvert) — vérifier que la branche ne régresse pas le banc.
6. **Validation VPS** (opérateur) : le **flux réel** (SSH `cni.sh`, kubeadm
   auto-detect, rapatriement admin.conf) se révèle au run sur le VPS — les tests
   unitaires couvrent la logique de branchement, pas le flux. Inhérent à une 1re
   implémentation cloud (ADR 0031).

## Hors périmètre

- **Provisioning IaC cloud** (OpenTofu, ADR 0032) — reste un stub. Le VPS
  préexiste ; on l'installe, on ne le provisionne pas.
- **Émission d'`ansible_host`** par le template `hosts.yaml.j2` (le nœud est
  résolu par nom) — chantier séparé, non requis (`control_plane_ip` vide).
- **HA control plane** (`ha-3cp`) — ce plan cible mono-CP / multi-nœuds non-HA
  (le `CP_IP=""` auto-detect vaut pour le CP primaire).
