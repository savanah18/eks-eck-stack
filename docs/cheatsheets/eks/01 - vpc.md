# Create and configure the VPC

This guide creates the core networking resources for the EKS environment in
`us-east-2`:

- A VPC using `10.0.0.0/16`
- An S3 VPC endpoint
- A private subnet
- An internet gateway
- A private route table with a default route through a regional NAT gateway
- Route-table associations for the private subnets

The commands are written as a sequential workflow. Run each command only after
the preceding resource has been created and substitute the returned resource
IDs where indicated. The default route is added after the NAT gateway becomes
available.

## Before you begin

1. Configure the AWS CLI with credentials that can create and modify VPC
   resources.
2. Confirm the target AWS Region. These commands use `us-east-2`; add
   `--region us-east-2` to each command or configure it as the CLI default.
3. Replace every value that starts with `preview-` with the actual ID returned
   by the corresponding `create` command. These values are examples, not valid
   AWS resource IDs.
4. Confirm that the subnet ID used in the route-table association is the
   intended private subnet. The example below uses `preview-subnet-private-5`
   while the subnet created in this guide is named
   `emirates-demo-subnet-private3-us-east-2c`.

## 1. Create the VPC

Create a VPC with a `/16` IPv4 address range and tag it for identification.
IPv6 addressing is not enabled by this command.

```bash
aws ec2 create-vpc \
  --cidr-block '10.0.0.0/16' \
  --no-amazon-provided-ipv6-cidr-block \
  --instance-tenancy 'default' \
  --tag-specifications \
    '{"ResourceType":"vpc","Tags":[{"Key":"Name","Value":"emirates-demo-vpc"}]}'
```

Enable DNS hostnames in the new VPC, then verify the VPC configuration:

```bash
aws ec2 modify-vpc-attribute \
  --vpc-id 'preview-vpc-1234' \
  --enable-dns-hostnames '{"Value":true}'

aws ec2 describe-vpcs \
  --vpc-ids 'preview-vpc-1234'
```

Record the VPC ID for the remaining commands.

## 2. Create the S3 VPC endpoint

Create an endpoint for S3 in the VPC. The endpoint lets resources access S3
without relying on the public internet path.

```bash
aws ec2 create-vpc-endpoint \
  --vpc-id 'preview-vpc-1234' \
  --service-name 'com.amazonaws.us-east-2.s3' \
  --tag-specifications \
    '{"ResourceType":"vpc-endpoint","Tags":[{"Key":"Name","Value":"emirates-demo-vpce-s3"}]}'
```

Record the returned VPC endpoint ID. Its route tables are associated later.

## 3. Create the private subnet

Create the private subnet in Availability Zone `us-east-2c`:

```bash
aws ec2 create-subnet \
  --vpc-id 'preview-vpc-1234' \
  --cidr-block '10.0.6.0/24' \
  --availability-zone 'us-east-2c' \
  --tag-specifications \
    '{"ResourceType":"subnet","Tags":[{"Key":"Name","Value":"emirates-demo-subnet-private3-us-east-2c"}]}'
```

Record the returned subnet ID. A subnet is private when its route table does
not send internet-bound traffic directly to an internet gateway.

## 4. Create and attach the internet gateway

Create an internet gateway and attach it to the VPC:

```bash
aws ec2 create-internet-gateway \
  --tag-specifications \
    '{"ResourceType":"internet-gateway","Tags":[{"Key":"Name","Value":"emirates-demo-igw"}]}'

aws ec2 attach-internet-gateway \
  --internet-gateway-id 'preview-igw-1234' \
  --vpc-id 'preview-vpc-1234'
```

Record the returned internet gateway ID before running the attach command.

## 5. Create the private route table

Create a route table for the private subnet and add a default route through
the regional NAT gateway:

```bash
aws ec2 create-route-table \
  --vpc-id 'preview-vpc-1234' \
  --tag-specifications \
    '{"ResourceType":"route-table","Tags":[{"Key":"Name","Value":"emirates-demo-rtb-private3-us-east-2c"}]}'
```

Record the returned route table ID. The default route is added after the NAT
gateway is available.

Associate the route table with the intended private subnet:

```bash
aws ec2 associate-route-table \
  --route-table-id 'preview-rtb-private-3' \
  --subnet-id 'preview-subnet-private-5'
```

Inspect the existing route tables to verify the associations:

```bash
aws ec2 describe-route-tables \
  --route-table-ids \
    'preview-rtb-public-0' \
    'preview-rtb-private-1' \
    'preview-rtb-private-2' \
    'preview-rtb-private-3'
```

## 6. Associate the S3 endpoint with private route tables

Add the private route tables to the S3 endpoint:

```bash
aws ec2 modify-vpc-endpoint \
  --vpc-endpoint-id 'preview-vpce-1234' \
  --add-route-table-ids \
    'preview-rtb-private-1' \
    'preview-rtb-private-2' \
    'preview-rtb-private-3'
```

## 7. Create and verify the regional NAT gateway

Create a public, regional NAT gateway. A public NAT gateway requires a public
subnet and an Elastic IP allocation in the complete network design.

```bash
aws ec2 create-nat-gateway \
  --vpc-id 'preview-vpc-1234' \
  --connectivity-type 'public' \
  --availability-mode 'regional' \
  --tag-specifications \
    '{"ResourceType":"natgateway","Tags":[{"Key":"Name","Value":"emirates-demo-regional-nat"}]}'
```

Wait until the NAT gateway is available, then verify it:

```bash
aws ec2 describe-nat-gateways \
  --nat-gateway-ids 'preview-regional-nat-1234' \
  --filter '{"Name":"state","Values":["available"]}'
```

Add the private route table's default route through the available NAT gateway:

```bash
aws ec2 create-route \
  --route-table-id 'preview-rtb-private-3' \
  --destination-cidr-block '0.0.0.0/0' \
  --nat-gateway-id 'preview-regional-nat-1234'
```

After the NAT gateway is available, verify that the private route table's
`0.0.0.0/0` route points to it. This gives resources in the private subnet
outbound internet access without making the subnet public.
