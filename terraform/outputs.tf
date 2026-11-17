output "network_id" {
  description = "ID сети диплома."
  value       = yandex_vpc_network.main.id
}

output "subnets" {
  description = "Подсети по зонам доступности."
  value = {
    for zone, subnet in yandex_vpc_subnet.main : zone => {
      id   = subnet.id
      cidr = subnet.v4_cidr_blocks[0]
    }
  }
}
