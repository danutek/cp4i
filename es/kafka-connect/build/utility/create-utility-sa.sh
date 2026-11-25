oc create sa utility-sa
oc adm policy add-scc-to-user anyuid -z utility-sa
oc adm policy add-scc-to-user privileged -z utility-sa
