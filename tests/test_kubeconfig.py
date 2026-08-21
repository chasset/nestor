"""Tests de la transformation PURE d'un kubeconfig rapatrié (nestor/kubeconfig.py, ADR 0081).

Pur : texte kubeconfig + paramètres → texte réécrit. Aucun nœud, aucun cluster.
"""

import os
import sys
import unittest

import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from nestor.kubeconfig import rewrite_kubeconfig  # noqa: E402

# admin.conf kubeadm typique : noms par défaut, endpoint INTERNE (cluster-api:6443).
_ADMIN_CONF = """\
apiVersion: v1
kind: Config
clusters:
  - name: kubernetes
    cluster:
      server: https://cluster-api:6443
      certificate-authority-data: aaa
users:
  - name: kubernetes-admin
    user:
      client-certificate-data: bbb
contexts:
  - name: kubernetes-admin@kubernetes
    context:
      cluster: kubernetes
      user: kubernetes-admin
current-context: kubernetes-admin@kubernetes
"""


class RewriteServer(unittest.TestCase):
    def test_server_endpoint_is_rewritten(self):
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF, server="https://127.0.0.1:6443"))
        self.assertEqual(out["clusters"][0]["cluster"]["server"], "https://127.0.0.1:6443")

    def test_server_none_keeps_original(self):
        # Prod (ADR 0115) : l'admin.conf porte déjà https://<ip-cp>:6443 (advertiseAddress
        # kubeadm = IP du nœud, joignable depuis le poste) → server=None GARDE l'original,
        # pas de réécriture (contrairement au banc dont l'IP interne Lima est injoignable).
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF, server=None))
        self.assertEqual(out["clusters"][0]["cluster"]["server"], "https://cluster-api:6443")

    def test_server_default_none_keeps_original(self):
        # défaut `server=None` (appel sans l'arg) → aussi garde l'original.
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF))
        self.assertEqual(out["clusters"][0]["cluster"]["server"], "https://cluster-api:6443")

    def test_server_none_with_context_name_still_renames(self):
        # server=None (garde endpoint) + context_name (rename) sont ORTHOGONAUX :
        # on peut garder l'endpoint prod tout en estampillant le contexte stack_id.
        out = yaml.safe_load(
            rewrite_kubeconfig(_ADMIN_CONF, server=None, context_name="edge-public")
        )
        self.assertEqual(
            out["clusters"][0]["cluster"]["server"], "https://cluster-api:6443"
        )  # endpoint inchangé
        self.assertEqual(out["clusters"][0]["name"], "edge-public")  # rename appliqué
        self.assertEqual(out["current-context"], "edge-public")

    def test_ca_data_is_preserved(self):
        # on ne touche QUE l'endpoint : le CA et les certs client restent intacts.
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF, server="https://10.0.0.11:6443"))
        self.assertEqual(out["clusters"][0]["cluster"]["certificate-authority-data"], "aaa")
        self.assertEqual(out["users"][0]["user"]["client-certificate-data"], "bbb")

    def test_tls_server_name_set_when_given(self):
        out = yaml.safe_load(
            rewrite_kubeconfig(
                _ADMIN_CONF, server="https://127.0.0.1:6443", tls_server_name="cluster-api"
            )
        )
        self.assertEqual(out["clusters"][0]["cluster"]["tls-server-name"], "cluster-api")

    def test_tls_server_name_absent_by_default(self):
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF, server="https://10.0.0.11:6443"))
        self.assertNotIn("tls-server-name", out["clusters"][0]["cluster"])


class RenameContext(unittest.TestCase):
    def test_default_names_renamed_uniquely(self):
        out = yaml.safe_load(
            rewrite_kubeconfig(_ADMIN_CONF, server="https://127.0.0.1:6443", context_name="banc")
        )
        self.assertEqual(out["clusters"][0]["name"], "banc")
        self.assertEqual(out["users"][0]["name"], "banc-admin")
        self.assertEqual(out["contexts"][0]["name"], "banc")
        self.assertEqual(out["current-context"], "banc")

    def test_context_references_rewired(self):
        # le contexte doit pointer les NOUVEAUX noms de cluster/user, sinon kubectl casse.
        out = yaml.safe_load(
            rewrite_kubeconfig(_ADMIN_CONF, server="https://127.0.0.1:6443", context_name="banc")
        )
        self.assertEqual(out["contexts"][0]["context"]["cluster"], "banc")
        self.assertEqual(out["contexts"][0]["context"]["user"], "banc-admin")

    def test_no_rename_when_context_name_absent(self):
        out = yaml.safe_load(rewrite_kubeconfig(_ADMIN_CONF, server="https://10.0.0.11:6443"))
        self.assertEqual(out["clusters"][0]["name"], "kubernetes")  # inchangé
        self.assertEqual(out["current-context"], "kubernetes-admin@kubernetes")


class Invalid(unittest.TestCase):
    def test_non_kubeconfig_raises(self):
        with self.assertRaises(ValueError):
            rewrite_kubeconfig("not: a: kubeconfig: at all", server="https://x:6443")

    def test_kubeconfig_without_clusters_raises(self):
        with self.assertRaises(ValueError):
            rewrite_kubeconfig("apiVersion: v1\nkind: Config\n", server="https://x:6443")


if __name__ == "__main__":
    unittest.main()
