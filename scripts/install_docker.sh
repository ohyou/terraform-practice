dnf -yq update
dnf -yq install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
dnf -yq update
dnf -yq install docker-ce
systemctl start docker