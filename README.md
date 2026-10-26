# Elastic Cluster on Kubernetes
---

## Introduction
### Problem Statement
This project involves designing and deploying an **Elastic Cluster on Kubernetes** that demonstrates practical understanding of running a stateful applications on top of an orchestration solution with **storage**, **scalability**, **reliability** and **observability** in consideration. 

### Challenges, Assumptions and Limitations
This project is limited to the following
- 

## Infrastructure Overview
This project is built on top of Amazon Web Services (AWS) as public cloud infrastructure provisioner - specifically **AWS Elastic Kubernetes** (AWS EKS). The target stateful applications that is the subject of deployment is an **Elastic Cluster** - a highly-available / scalable distributed search and analytics engine. 

The EKS Cluster is deployed over a **Virtual Private Cloud** with all the required and necessary networking requirements configured. Compute nodes provisioned on **multiple availability zones** across selected a selected region. Different sets **EKS managed node groups** is also provisioned representing different kind of compute requirements - with some node groups labeled for *autoscaling capabilities*. Different EKS cluster add-ons (Core DNS, CSI Driver, CNI, etc) are also added.

The Elastic Cluster is configured and deployed over an **Elastic Cloud on Kubernetes Operator**(ECK Operator) through *operator-based deployment pattern* with custom resources wrapped in an existing public helm chart. For this project, different **elasticsearch nodesets**(master, data, etc) with *dedicated affinity and spread contraints* for optimal availability. A dedicated **kibana deployment** is also added for **visualization** and more importantly for this project - *observability* and *monitoring*.  Additional **beats**  deployments are also deployed for *host/eck stack metrics collection*. 

**TODO** - Autoscaling

An **alb type ingress** is provisioned for kibana for internet-facing exposure with *necessary security protocols* setup. Multiple **kubernetes network policies** are provisioned to control ingress and egress traffic - as no network policies is configured by default. 

## Design 
The following details all significant design decisions and configuration. 

### Prerequisite
- An existing public account and IAM user credentials
- Access to tools like `helm`, `aws cli`, `helm`, and `terraform`


### AWS EKS Configuration and Dimensioning
#### VPC Configuration


### Infrastructure as a Code

### Elastic Cluster

## Scaling / Upgrade Procedures
### Upgrade Procedures
As most of the resources provisioned for this project are using terraform, upgrade procedures mostly revolves around updating necessary terraform resources accordingly. 

## Troubleshooting Steps for Consumers

## Monitoring Setup

## Challenges, Assumptions and Limitations