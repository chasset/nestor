#!/usr/bin/env bash
#
# Helpers purs pour bootstrap/first-access-root.sh (testés par bats, ADR 0049/0017).
# Aucune I/O, aucun SSH : le script DISTANT est une FONCTION (source unique du
# contenu — l'orchestration et le test bats partagent cette fonction, pas de
# dérive). `first-access-root.sh` rend le socle `debian` ATTENDU par
# `first-access.sh` JOIGNABLE PAR CLÉ + sudo NOPASSWD, puis LOCKE le mot de passe
# root (obligatoire). NE touche PAS à sshd (source unique = first-access.sh).
#
# Sur un VPS où `debian` existe déjà (ex. Contabo), la création est un no-op ;
# le script reste générique pour tout fournisseur IaaS livré en root.

# Renvoie le script distant (bash) exécuté en root sur le VPS : assure `debian`
# (key-only) + dépose la clé publique + sudo NOPASSWD + groupe sudo. Idempotent.
# NE locke PAS root ici : le lock est GATING sur la PREUVE d'accès debian (faite
# par l'orchestration APRÈS ce script — ne jamais fermer la sortie avant preuve).
remote_bootstrap_script() {
    cat <<'REMOTE'
#!/bin/bash
# Script distant (root) de first-access-root.sh. Assure le sudoer `debian`
# key-only + sudo NOPASSWD. NE touche PAS à sshd (source unique = first-access.sh).
# Idempotent (write_if_changed + gardes `id`/`grep`).
set -euo pipefail

SSH_PUBKEY="${SSH_PUBKEY:?SSH_PUBKEY (chemin de la clé publique) requis}"

# write_if_changed MODE DEST CONTENT — n'écrit qu'en cas de diff de contenu OU de
# mode (idempotence). Retourne 0 si (ré)écrit, 1 si déjà conforme. (Copié de
# bootstrap/first-access.sh — même idiomatique, source unique du drop-in sshd.)
write_if_changed() {
    local mode=$1 dest=$2 content=$3 want_mode=${mode#0}
    if [ -f "$dest" ]; then
        local cur cur_mode
        cur=$(cat "$dest"); cur_mode=$(stat -c '%a' "$dest")
        if [ "$cur" = "$content" ] && [ "$cur_mode" = "$want_mode" ]; then return 1; fi
    fi
    install -m "$mode" -D /dev/stdin "$dest" <<<"$content"
    return 0
}

# (1) Assure debian (idempotent). Sur un VPS où debian existe déjà (ex. Contabo),
#     c'est un no-op — le script reste générique pour tout fournisseur.
if id debian >/dev/null 2>&1; then
    echo "  → debian déjà présent"
else
    useradd -m -s /bin/bash debian
    echo "  → debian créé (useradd)"
fi

# (2) Dépose la clé publique de l'opérateur dans authorized_keys (additif, idempotent).
install -d -m 700 -o debian -g debian /home/debian/.ssh
ak=/home/debian/.ssh/authorized_keys
touch "$ak"; chmod 600 "$ak"; chown debian:debian "$ak"
if grep -qF "$(cat "$SSH_PUBKEY")" "$ak" 2>/dev/null; then
    echo "  → clé déjà présente pour debian"
else
    cat "$SSH_PUBKEY" >>"$ak"
    echo "  → clé publique déposée pour debian"
fi

# (3) sudo NOPASSWD pour debian (idempotent). first-access.sh re-assertera ce drop-in.
sudoers='debian ALL=(ALL) NOPASSWD: ALL'
if write_if_changed 0440 /etc/sudoers.d/90-debian-nopasswd "$sudoers"; then
    echo "  → sudo NOPASSWD posé"
else
    echo "  → sudo NOPASSWD déjà conforme"
fi

# (4) debian ∈ groupe sudo (idempotent — usermod -aG est additif, no-op si déjà membre).
usermod -aG sudo debian
echo "  → debian ∈ groupe sudo"
REMOTE
}

# Pure : le champ password shadow est-il verrouillé (ou sans mot de passe) ?
# Préfixe `!` (usermod -L) ou `*` (compte sans password, login impossible) → locked.
# Champ vide ou hash → non locked (à locker). Utilisé par l'orchestration pour
# n'émettre `usermod -L root` qu'en cas de besoin (idempotence du lock).
is_shadow_locked() {
    case "$1" in
        '!'* | '*') return 0 ;;
        *) return 1 ;;
    esac
}

# Pure : commande distante (root) lockant le mot de passe root. usermod -L
# (JAMAIS userdel — UID 0 invariant système : fsck, recovery single-user, daemons).
# Appelée par l'orchestration APRÈS preuve d'accès debian. Idempotente (usermod -L
# sur un compte déjà locké = no-op).
lock_root_command() {
    printf 'usermod -L root'
}
