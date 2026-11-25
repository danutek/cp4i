oc create sa ubuntu
oc adm policy add-scc-to-user anyuid -z ubuntu	
oc adm policy add-scc-to-user privileged -z ubuntu
