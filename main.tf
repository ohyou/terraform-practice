locals {
  openstack = "${map(
    "auth_url",     "https://api.selvpc.ru/identity/v3",
    "domain_name",  "${lookup(var.cloud, "domain_name")}",
    "tenant_name",  "${lookup(var.cloud, "tenant_name")}",
    "user_name",    "${lookup(var.cloud, "user_name")}",
    "password",     "${lookup(var.cloud, "password")}",
    "region",       "${lookup(var.cloud, "region", "ru-1")}",
  )}"

  cloud = "${map(
    "name",   "${local.openstack["tenant_name"]}",
    "region", "${local.openstack["region"]}",
    "zone",   "${lookup(var.cloud, "zone", "${local.openstack["region"]}a")}"
  )}"
}

provider "openstack" {
  auth_url    = "${local.openstack["auth_url"]}"
  domain_name = "${local.openstack["domain_name"]}"
  tenant_name = "${local.openstack["tenant_name"]}"
  user_name   = "${local.openstack["user_name"]}"
  password    = "${local.openstack["password"]}"
  region      = "${local.openstack["region"]}"
}

module "keypair" {
  source  = "github.com/kodix/terraform-selectel/modules/keypair"
  cloud   = "${local.cloud}"
  private = "${file("~/.ssh/id_rsa")}"
}

module "network" {
  source = "github.com/kodix/terraform-selectel/modules/network"
  cloud  = "${local.cloud}"

  lan {
    cidr    = "192.168.0.0/24"
    gateway = "192.168.0.254"
  }

  wan {
    uuid = "af3d0c8c-382e-4d82-8954-98674b91d9a9"
  }

  dns = [
    "8.8.8.8",
    "1.1.1.1",
  ]
}

module "manager" {
  source  = "github.com/kodix/terraform-selectel/modules/instance"
  cloud   = "${local.cloud}"
  name    = "manager"
  keypair = "${module.keypair.name}"

  lan {
    uuid    = "${module.network.lan["uuid"]}"
    address = "${module.network.lan["gateway"]}"
  }

  wan {
    uuid = "${module.network.wan["uuid"]}"
  }

  flavor {
    cpu = 2
    ram = 2048
  }

  disk {
    size  = 10
    type  = "fast"
    image = "Fedora 28 64-bit"
  }
}

module "worker" {
  source  = "github.com/kodix/terraform-selectel/modules/instance"
  cloud   = "${local.cloud}"
  name    = "worker"
  count   = 2
  keypair = "${module.keypair.name}"

  lan {
    uuid = "${module.network.lan["uuid"]}"
  }

  flavor {
    cpu = 2
    ram = 2048
  }

  disk {
    size  = 10
    type  = "fast"
    image = "Fedora 28 64-bit"
  }
}

resource "null_resource" "manager-init" {
  depends_on = ["module.manager"]

  connection {
    host        = "${lookup(module.manager.instance[0], "wan")}"
    private_key = "${module.keypair.private}"
  }

  provisioner "file" {
    source      = "./scripts/config_nat.sh"
    destination = "/tmp/config_nat.sh"
  }

  provisioner "file" {
    source      = "./scripts/fetch_tokens.sh"
    destination = "/tmp/fetch_tokens.sh"
  }

  provisioner "file" {
    source      = "./scripts/install_docker.sh"
    destination = "/tmp/install_docker.sh"
  }

  provisioner "file" {
    source      = "./scripts/install_consul.sh"
    destination = "/tmp/install_consul.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.ingress.rendered}"
    destination = "/tmp/docker-compose.yml"
  }

  #docker service up -c -f
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_nat.sh",
      "chmod +x /tmp/fetch_tokens.sh",
      "chmod +x /tmp/install_docker.sh",
      "chmod +x /tmp/install_consul.sh",
      "/tmp/install_docker.sh",
      "/tmp/config_nat.sh ${module.network.lan["cidr"]} ${lookup(module.manager.instance[0], "wan")}",
      "/tmp/install_consul.sh",
      "docker swarm init --advertise-addr ${lookup(module.manager.instance[0], "lan")}",
      "docker network rm ingress -f",
      "docker network create --attachable --scope swarm ingress",
      "docker stack deploy -c /tmp/docker-compose.yml ingress",
    ]

    //"echo \"${data.template_file.ingress.rendered}\" > /tmp/docker-compose.yml",
    //"docker-compose -f /tmp/docker-compose.yml up",
  }
}

data "template_file" "ingress" {
  template = "${file("./stacks/ingress/docker-compose.yml")}"

  vars = {
    wan = "${lookup(module.manager.instance[0], "wan")}"
  }
}

resource "null_resource" "worker-init" {
  depends_on = ["module.worker", "null_resource.manager-init"]

  count = 2

  connection {
    bastion_host        = "${lookup(module.manager.instance[0], "wan")}"
    bastion_private_key = "${module.keypair.private}"
    host                = "${lookup(module.worker.instance[count.index], "lan")}"
    private_key         = "${module.keypair.private}"
    timeout             = "10s"
  }

  provisioner "file" {
    source      = "./scripts/install_docker.sh"
    destination = "/tmp/install_docker.sh"
  }

  provisioner "file" {
    source      = "./scripts/install_consul.sh"
    destination = "/tmp/install_consul.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install_docker.sh",
      "chmod +x /tmp/install_consul.sh",
      "/tmp/install_docker.sh",
      "/tmp/install_consul.sh",
      "docker swarm join --token ${data.external.swarm_tokens.result.worker} ${lookup(module.manager.instance[0], "lan")}:2377",
    ]
  }
}

data "external" "swarm_tokens" {
  depends_on = ["module.manager", "null_resource.manager-init"]
  program    = ["./scripts/fetch_tokens.sh"]

  query = {
    host = "${lookup(module.manager.instance[0], "wan")}"
  }
}
