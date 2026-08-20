# Plateforme

Services transverses du cluster (au-delà du bootstrap K8s et du stockage Ceph).

| Composant                                                           | Rôle                                                            |
| ------------------------------------------------------------------- | --------------------------------------------------------------- |
| [`argocd/`](/nestor/platform/argocd/)                               | GitOps applicatif (Argo CD v3.4.3, cf. ADR 0022)                |
| [`cert-manager/`](/nestor/platform/cert-manager/)                   | TLS de bordure via CA interne (cf. ADR 0021)                    |
| [`cloudnative-pg/`](/nestor/platform/cloudnative-pg/)               | PostgreSQL managé (socle DataOps — cf. ADR 0024)                |
| [`container-registry/`](/nestor/platform/container-registry/)       | Registry d'images interne (distribution v3, RBD ×3)             |
| [`dagster/`](/nestor/platform/dagster/)                             | Orchestrateur DataOps (cf. ADR 0026)                            |
| [`gitea/`](/nestor/platform/gitea/)                                 | Forge git intra-banc (air-gapped, source GitOps — cf. ADR 0044) |
| [`k8s-dashboard/`](/nestor/platform/k8s-dashboard/)                 | Kubernetes Dashboard (Helm, tokens éphémères — cf. ADR 0010)    |
| [`kube-prometheus-stack/`](/nestor/platform/kube-prometheus-stack/) | Observabilité palier 2 : Prometheus + Grafana (cf. ADR 0016)    |
| [`loki/`](/nestor/platform/loki/)                                   | Agrégation des logs (cf. ADR 0016)                              |
| [`mailpit/`](/nestor/platform/mailpit/)                             | Puits SMTP + UI de test (destination mail de la plateforme)     |
| [`marquez/`](/nestor/platform/marquez/)                             | Store de lineage OpenLineage (cf. ADR 0028)                     |
| [`metrics-server/`](/nestor/platform/metrics-server/)               | Métriques CPU/mémoire (`kubectl top`, HPA — cf. ADR 0016)       |
| [`network-policies/`](/nestor/platform/network-policies/)           | NetworkPolicies default-deny par namespace (audit P6 #22)       |
| [`hardware.md`](/nestor/platform/hardware/)                         | Inventaire matériel des nœuds (serveurs lames)                  |

**Exposition des UI** : depuis
l'[ADR 0092](/nestor/docs/decisions/0092-exposition-hostport-l4/), les UI sont
servies en **L4** (`NodePort`/`hostPort` sur l'IP du nœud,
`http://<IP-nœud>:<port>`) — plus de Gateway L7 ni de dossier
`platform/cilium-expo/` (retiré). Les features Cilium LB-IPAM/Gateway restent
armées par `bootstrap/cni.sh` (chemin de prod optionnel).

Chaque composant a son propre README avec installation et décisions assumées
(`mlflow/`, `redcap/`, `seaweedfs/` inclus — cf. la pile complète dans
[`docs/composants.md`](/nestor/docs/composants/), source canonique). Vue
d'ensemble du dépôt :
[README racine](https://github.com/chasset/nestor/blob/main/README.md) ·
[Par où commencer](/nestor/docs/demarrage/).
