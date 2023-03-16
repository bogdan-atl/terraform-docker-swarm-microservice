terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.80"
}

provider "yandex" {
  service_account_key_file = "key.json"
  cloud_id                 = "id
  folder_id                = "token"
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "network" {
  name = "my-network"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "my-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_compute_instance" "ubuntu" {
  count        = 3
  name         = "${count.index == 0 ? "master" : "worker-${count.index}"}"
  zone         = "ru-central1-a"
  platform_id  = "standard-v2"
  boot_disk {
    initialize_params {
      image_id = "fd8emvfmfoaordspe1jr"
      size = 20
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }
  resources {
    cores  = 2
    memory = 2
  }
  metadata = {
    ssh-keys = "ubuntu:${file("./id_rsa.pub")}"
  }
}


resource "null_resource" "docker_swarm" {
  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://get.docker.com | sh",
      "sudo usermod -aG docker $USER",
      "sudo apt install -y docker-compose",
      "sudo docker swarm init --advertise-addr ${yandex_compute_instance.ubuntu.0.network_interface.0.ip_address}:2377",
      "sudo docker swarm join-token worker -q > /tmp/worker_token",
      "sudo docker swarm join-token manager -q > /tmp/manager_token",
      "sleep 10",
      "echo COMPLETED"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./id_rsa")
      host        = yandex_compute_instance.ubuntu.0.network_interface.0.nat_ip_address
    }
  }

    provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ./id_rsa ubuntu@${yandex_compute_instance.ubuntu.0.network_interface.0.nat_ip_address}:/tmp/worker_token ./worker_token"
  }
}

resource "null_resource" "docker_swarm_worker_1" {
  depends_on = [null_resource.docker_swarm]

  provisioner "file" {
    source      = "./worker_token"
    destination = "/tmp/worker_token"

  connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file("./id_rsa")
        host        = yandex_compute_instance.ubuntu.1.network_interface.0.nat_ip_address
    }
  }


  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://get.docker.com | sh",
      "sudo usermod -aG docker $USER",
      "sudo apt install -y docker-compose",
      "sudo docker swarm join --token $(cat /tmp/worker_token) ${yandex_compute_instance.ubuntu.0.network_interface.0.ip_address}:2377",
      "sleep 10",
      "echo COMPLETED"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./id_rsa")
      host        = yandex_compute_instance.ubuntu.1.network_interface.0.nat_ip_address
    }
  }
}

resource "null_resource" "docker_swarm_worker_2" {
  depends_on = [null_resource.docker_swarm]
  provisioner "file" {
    source      = "./worker_token"
    destination = "/tmp/worker_token"

  connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file("./id_rsa")
        host        = yandex_compute_instance.ubuntu.2.network_interface.0.nat_ip_address
    }

  }
  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://get.docker.com | sh",
      "sudo usermod -aG docker $USER",
      "sudo apt install -y docker-compose",
      "sudo docker swarm join --token $(cat /tmp/worker_token) ${yandex_compute_instance.ubuntu.0.network_interface.0.ip_address}:2377",
      "sleep 10",
      "echo COMPLETED"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./id_rsa")
      host        = yandex_compute_instance.ubuntu.2.network_interface.0.nat_ip_address
    }
  }
}
resource "null_resource" "docker_swarm_master" {
  depends_on = [null_resource.docker_swarm_worker_1, null_resource.docker_swarm_worker_2]

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ./id_rsa docker-compose.yml ubuntu@${yandex_compute_instance.ubuntu.0.network_interface.0.nat_ip_address}:~/"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo docker stack deploy --compose-file ~/docker-compose.yml sockshop-swarm"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./id_rsa")
      host        = yandex_compute_instance.ubuntu.0.network_interface.0.nat_ip_address
    }
  }

}

