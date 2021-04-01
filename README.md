# Letsencrypt pod

Run this pod in strictly a single instance in the cluster. That is important since if traffic is balanced over multiple instances then it won't work.

After having imported the pod config templates to the cluster (which automatically happens when attaching the pod):
update the config file `certs_list/certs.txt` inside the cluster `./_config/letsencrypt` dir with the domains you want certificates generated for.
One row per certificate, multiple domains per row is allowed.
