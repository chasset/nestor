# Applications

Charges applicatives déployées sur le cluster (calcul / services de recherche).

| Application                         | Rôle                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------- |
| [`rstudio/`](/nestor/apps/rstudio/) | RStudio Server (image `rocker`) sur PVC RBD — cf. ADR 0012              |
| [`redcap/`](/nestor/apps/redcap/)   | REDCap (PHP/Apache, image maison) + MariaDB autonome — cf. README dédié |

> Les exemples de validation du stockage (WordPress/MySQL) vivent sous
> [`storage/ceph/wordpress/`](/nestor/storage/ceph/wordpress/), pas ici.

Vue d'ensemble du dépôt :
[README racine](https://github.com/chasset/nestor/blob/main/README.md) ·
[Par où commencer](/nestor/docs/demarrage/).
