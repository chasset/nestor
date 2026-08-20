# StorageClasses

Définition des classes de stockage Ceph utilisables par les workloads du
cluster.

## Layout

| Dossier / fichier                                                                                                      | Rôle                                                |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| [`block-replicated.yaml`](https://github.com/chasset/nestor/blob/main/storage/ceph/storageClass/block-replicated.yaml) | Stockage bloc répliqué (RBD) — la classe par défaut |
| [`block-ec-retain.yaml`](https://github.com/chasset/nestor/blob/main/storage/ceph/storageClass/block-ec-retain.yaml)   | Stockage bloc erasure-coded, `Retain`               |
| [`block-ec-delete.yaml`](https://github.com/chasset/nestor/blob/main/storage/ceph/storageClass/block-ec-delete.yaml)   | Stockage bloc erasure-coded, `Delete`               |
| [`filesystem/`](/nestor/storage/ceph/storageClass/filesystem/)                                                         | StorageClass CephFS (ReadWriteMany)                 |
| [`datalake/`](/nestor/storage/ceph/storageClass/datalake/)                                                             | Object store S3-compatible (datalake)               |
| [`examples/`](https://github.com/chasset/nestor/blob/main/storage/ceph/storageClass/examples)                          | Exemples d'usage (PVC, services, etc.)              |
