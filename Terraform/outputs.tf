output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.my-vpc.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [aws_subnet.Pub-Subnet.id, aws_subnet.Pub-Subnet-2.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = [aws_subnet.Pvt-Subnet.id, aws_subnet.Pvt-Subnet-2.id]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.gw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.ram.id
}

output "public_route_table_id" {
  description = "ID of public route table"
  value       = aws_route_table.Pub-Route-Table.id
}

output "private_route_table_id" {
  description = "ID of private route table"
  value       = aws_route_table.Pvt-Route-Table.id
}
