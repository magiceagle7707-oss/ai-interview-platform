resource "aws_vpc" "my-vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  tags = {
    Name        = var.vpc_name
    Environment = var.environment
    Project     = var.project
    created_by  = var.created_by
  }

  lifecycle {
    ignore_changes = [tags]
    #     prevent_destroy = true
  }

  provisioner "local-exec" {
    command = "echo ${self.id} >> file.txt"
  }
}

resource "aws_subnet" "Pub-Subnet" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = var.pub_subnet_cidr
  availability_zone = "ap-south-1b"

  tags = {
    Name        = var.public_subnet_name
    Environment = var.environment
    Project     = var.project
    created_by  = var.created_by
  }

  lifecycle {
    ignore_changes = [tags]
    #     prevent_destroy = true
  }

  provisioner "local-exec" {
    command = "echo ${self.id} > file.txt"
  }
}

resource "aws_subnet" "Pub-Subnet-2" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = var.pub_subnet_cidr_2
  availability_zone = "ap-south-1a"

  tags = {
    Name        = var.public_subnet_name
    Environment = var.environment
    Project     = var.project
    created_by  = var.created_by
  }

  lifecycle {
    ignore_changes = [tags]
    #     prevent_destroy = true
  }
}

resource "aws_subnet" "Pvt-Subnet" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = var.pvt_subnet_cidr
  availability_zone = "ap-south-1a"

  tags = {
    Name        = var.subnet_name
    Environment = var.environment
    Project     = var.project
    created_by  = var.created_by
  }

  lifecycle {
    ignore_changes = [tags]
    #     prevent_destroy = true
  }
}

resource "aws_subnet" "Pvt-Subnet-2" {
  vpc_id            = aws_vpc.my-vpc.id
  cidr_block        = var.pvt_subnet_cidr_2
  availability_zone = "ap-south-1b"

  tags = {
    Name        = var.subnet_name
    Environment = var.environment
    Project     = var.project
    created_by  = var.created_by
  }

  lifecycle {
    ignore_changes = [tags]
    #     prevent_destroy = true
  }
}

resource "aws_route_table" "Pub-Route-Table" {
  vpc_id = aws_vpc.my-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "App-Route-Table"
  }
}

resource "aws_route_table" "Pvt-Route-Table" {
  vpc_id = aws_vpc.my-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ram.id
  }

  tags = {
    Name = "DB-Route-Table"
  }
}

resource "aws_route_table_association" "Pub-Route-Table-Association" {
  subnet_id      = aws_subnet.Pub-Subnet.id
  route_table_id = aws_route_table.Pub-Route-Table.id
}

resource "aws_route_table_association" "Pub-Route-Table-Association-1" {
  subnet_id      = aws_subnet.Pub-Subnet-2.id
  route_table_id = aws_route_table.Pub-Route-Table.id
}

resource "aws_route_table_association" "Pvt-Route-Table-Association" {
  subnet_id      = aws_subnet.Pvt-Subnet.id
  route_table_id = aws_route_table.Pvt-Route-Table.id
}

resource "aws_route_table_association" "Pvt-Route-Table-Association-1" {
  subnet_id      = aws_subnet.Pvt-Subnet-2.id
  route_table_id = aws_route_table.Pvt-Route-Table.id
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "main"
  }
}

resource "aws_eip" "lb" {
  # instance = aws_instance.web.id
  domain = "vpc"
}

resource "aws_nat_gateway" "ram" {
  allocation_id = aws_eip.lb.id
  subnet_id     = aws_subnet.Pub-Subnet.id

  tags = {
    Name = "gw NAT"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}
