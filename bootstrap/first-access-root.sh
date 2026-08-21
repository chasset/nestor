#!/usr/bin/env bash
#
# bootstrap/first-access-root.sh — PRÉALABLE à first-access.sh pour un VPS livré
# en root (mot de passe panel) sans accès par clé sur debian. Connecté en root,
# assure le sudoer `debian` attendu par first-access.sh (clé + sudo NOPASSWD),
# VÉRIFIE l'accès debian, puis LOCKE le mot de passe root (obligatoire). NE touche
# PAS à sshd (source unique = first-access.sh) — enchaîner ensuite first-access.sh.
#
# Sur un VPS où `debian` existe déjà (ex. Contabo), la création est un no-op ; le
# script reste générique pour tout fournisseur IaaS livré en root (valeur réelle
# ici : déposer ta clé sur debian + assurer sudo/NOPASSWD + locker root).
#
# Usage:
#   bootstrap/first-access-root.sh <ip>...
#   (ex. VPS Contabo : bash bootstrap/first-access-root.sh 203.0.113.42)
#
# Variables d'environnement:
#   SSH_PUBKEY   clé publique à déposer (défaut: ~/.ssh/id_ed25519.pub)
#
# Séquence (idempotente, par hôte) :
#   1. ssh-copy-id root@<ip>              # prompt mot de passe root la 1re fois (no-op si clé déjà posée)
#   2. assure debian + dépose clé + sudo NOPASSWD (script distant, root)
#   3. PREUVE d'accès debian (SSH clé + sudo -n)   # garde-fou anti-lockout
#   4. LOCKE root (usermod -L root, obligatoire)    # APRÈS preuve — jamais avant
#
# Sécurité : root n'est JAMAIS locké avant que l'accès debian (clé + sudo -n) ne
# soit PROUVÉ. Un échec de preuve ABANDONNE sans locker (exit 1) — on ne ferme pas
# la seule porte de sortie sans certitude que l'autre ouvre.
#
# Enchaîner ensuite : bash bootstrap/first-access.sh <ip>
set -euo pipefail

# shellcheck source=bootstrap/lib/first-access-root.sh
source "$(dirname "$0")/lib/first-access-root.sh"

SSH_PUBKEY=${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}
export SSH_PUBKEY
# Clé privée correspondante (pour BatchMode : pas de prompt mot de passe, échec net).
if [[ "$SSH_PUBKEY" == *.pub ]]; then SSH_KEY=${SSH_PUBKEY%.pub}; else SSH_KEY=$SSH_PUBKEY; fi
export SSH_KEY

hosts=("$@")
if [ "${#hosts[@]}" -eq 0 ]; then
    echo "usage: bootstrap/first-access-root.sh <ip>... (≥1 hôte requis)" >&2
    echo "       ex. : bash bootstrap/first-access-root.sh 203.0.113.42" >&2
    exit 2
fi

if [ ! -f "$SSH_PUBKEY" ]; then
    echo "ERREUR : clé publique introuvable : $SSH_PUBKEY" >&2
    echo "        Générer avec : ssh-keygen -t ed25519" >&2
    exit 1
fi

for h in "${hosts[@]}"; do
    echo
    echo "== $h =="

    # (1) Dépose la clé sur root (prompt mot de passe root la 1re fois ; no-op si déjà posée).
    #     Tolérant (|| true) : l'étape (3) de preuve rattrape un réel échec (clé absente
    #     → BatchMode ssh KO → abandon net).
    ssh-copy-id -i "$SSH_PUBKEY" "root@$h" || true

    # (2) Dépose le script distant + la clé, exécute en root (assure debian + clé + sudo).
    remote_bootstrap_script | ssh "root@$h" 'cat > /tmp/first-access-root.sh'
    scp -q "$SSH_PUBKEY" "root@$h:/tmp/operator.pub"
    if ! ssh -t "root@$h" \
        'SSH_PUBKEY=/tmp/operator.pub bash /tmp/first-access-root.sh; rc=$?; rm -f /tmp/operator.pub /tmp/first-access-root.sh; exit $rc'; then
        echo "ERREUR : échec du script distant sur $h" >&2
        exit 1
    fi

    # (3) PREUVE d'accès debian (garde-fou anti-lockout) : SSH clé (BatchMode, pas de
    #     prompt) + sudo -n (NOPASSWD). Si KO → ABANDON SANS locker (exit 1).
    if ! ssh -o BatchMode=yes -i "$SSH_KEY" "debian@$h" 'sudo -n true' >/dev/null 2>&1; then
        echo "ERREUR : accès debian non vérifié (clé ou sudo -n KO) sur $h" >&2
        echo "        → root NON locké, abandon (ne pas fermer la sortie sans preuve)." >&2
        exit 1
    fi
    echo "  → accès debian vérifié (clé + sudo -n NOPASSWD)"

    # (4) LOCKE root (obligatoire, APRÈS preuve). Idempotent : no-op si déjà sans mot de passe.
    root_pw=$(ssh -o BatchMode=yes -i "$SSH_KEY" "root@$h" 'getent shadow root 2>/dev/null | cut -d: -f2')
    if is_shadow_locked "$root_pw"; then
        echo "  → root déjà sans mot de passe, lock no-op"
    else
        ssh -o BatchMode=yes -i "$SSH_KEY" "root@$h" "$(lock_root_command)"
        echo "  → root password locké (usermod -L root)"
    fi
done

echo
echo "Préalable terminé sur : ${hosts[*]}"
echo "Étape suivante : bash bootstrap/first-access.sh ${hosts[*]}"
