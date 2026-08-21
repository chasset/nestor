#!/usr/bin/env bats
#
# Tests des fonctions pures de first-access-root.sh (préalable à first-access.sh
# pour un VPS livré en root). Aucun cluster/VPS requis : on source la lib et on
# vérifie le contenu du script distant + la détection de lock shadow. Même
# patron que state-classify.bats / bootstrap-fault.bats.

setup() {
    # shellcheck source=../../bootstrap/lib/first-access-root.sh
    source "${BATS_TEST_DIRNAME}/../../bootstrap/lib/first-access-root.sh"
}

# ─── remote_bootstrap_script : contenu (le contrat du script distant) ───────

@test "remote_bootstrap_script crée/assure debian (idempotent : id || useradd)" {
    run remote_bootstrap_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"useradd -m -s /bin/bash debian"* ]]
    [[ "$output" == *"id debian"* ]]
}

@test "remote_bootstrap_script dépose la clé publique pour debian (additif, idempotent)" {
    run remote_bootstrap_script
    [[ "$output" == *"/home/debian/.ssh/authorized_keys"* ]]
    [[ "$output" == *"grep -qF"* ]]
}

@test "remote_bootstrap_script pose sudo NOPASSWD pour debian (write_if_changed)" {
    run remote_bootstrap_script
    [[ "$output" == *"debian ALL=(ALL) NOPASSWD: ALL"* ]]
    [[ "$output" == *"/etc/sudoers.d/90-debian-nopasswd"* ]]
    [[ "$output" == *"write_if_changed"* ]]
}

@test "remote_bootstrap_script ajoute debian au groupe sudo" {
    run remote_bootstrap_script
    [[ "$output" == *"usermod -aG sudo debian"* ]]
}

@test "remote_bootstrap_script NE touche PAS à sshd (source unique = first-access.sh)" {
    run remote_bootstrap_script
    [[ "$output" != *"sshd_config"* ]]
    [[ "$output" != *"PermitRootLogin"* ]]
    [[ "$output" != *"PasswordAuthentication"* ]]
    [[ "$output" != *"AllowUsers"* ]]
}

@test "remote_bootstrap_script NE locke PAS root (le lock est gating sur preuve, hors script distant)" {
    # Le lock vient APRÈS la preuve d'accès debian (étape 3 de l'orchestration) :
    # il ne doit JAMAIS figurer dans le script distant, sous peine de locker avant preuve.
    run remote_bootstrap_script
    [[ "$output" != *"usermod -L root"* ]]
    [[ "$output" != *"userdel"* ]]
}

@test "remote_bootstrap_script NE pose PAS de mot de passe debian (key-only par construction)" {
    # useradd sans -p laisse le compte verrouillé (! dans shadow) → key-only.
    # Aucune commande de pose de mot de passe (chpasswd / usermod -p) sur debian.
    # NB : "NOPASSWD" et "90-debian-nopasswd" (sudoers) contiennent la sous-chaîne
    # "passwd" mais ne POSNT aucun mot de passe — on cible les commandes, pas la chaîne.
    run remote_bootstrap_script
    [[ "$output" != *"chpasswd"* ]]
    [[ "$output" != *"usermod -p"* ]]
    [[ "$output" != *"passwd -d"* ]]
}

# ─── is_shadow_locked (détection de lock, pure) ────────────────────────────

@test "is_shadow_locked : !hash → locked (usermod -L posé)" {
    run is_shadow_locked '!$6$rounds=...hash'
    [ "$status" -eq 0 ]
}

@test "is_shadow_locked : !! → locked (double-lock toléré)" {
    run is_shadow_locked '!!$6$hash'
    [ "$status" -eq 0 ]
}

@test "is_shadow_locked : * → locked (compte sans mot de passe)" {
    run is_shadow_locked '*'
    [ "$status" -eq 0 ]
}

@test "is_shadow_locked : hash → non locked (à locker)" {
    run is_shadow_locked '$6$rounds=...hash'
    [ "$status" -ne 0 ]
}

@test "is_shadow_locked : vide → non locked (à locker)" {
    run is_shadow_locked ''
    [ "$status" -ne 0 ]
}

# ─── lock_root_command (le lock, pas la suppression) ───────────────────────

@test "lock_root_command = usermod -L root (lock, JAMAIS userdel)" {
    run lock_root_command
    [ "$status" -eq 0 ]
    [ "$output" = "usermod -L root" ]
    [[ "$output" != *"userdel"* ]]
    [[ "$output" != *"passwd -d"* ]]
}

# ─── orchestration : garde d'arguments (≥1 hôte requis) ────────────────────

@test "sans argument → exit 2 + usage (≥1 hôte requis)" {
    run bash "${BATS_TEST_DIRNAME}/../../bootstrap/first-access-root.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage"* ]]
    [[ "$output" == *"≥1 hôte requis"* ]]
}
