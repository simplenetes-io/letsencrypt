# Letsencrypt pod

Run this pod in strictly a single instance in the cluster. That is important since if traffic is balanced over multiple instances then it won't work.

Update the config file `certs_list/certs.txt` with the domains you want certificates for. One row per certificate, multiple domains per row is allowed.
