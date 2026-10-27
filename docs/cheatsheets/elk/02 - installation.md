# Installation
## Deploy ECK Operator
1. Add/Update Elastic Helm Repo
```
helm repo add elastic https://helm.elastic.co
helm repo update
```
2. Configure `ECK Operator` to be scheduled on dedicated node group
```
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-group
          operator: In
          values:
          - system

```

32.  Install ECK Operator
```
helm install elastic-operator elastic/eck-operator -n elastic-system --create-namespace -f ../../iac/terraform/eks/values/eck-operator-values-system.yaml
```

The Terraform deployment uses the smaller override at
`iac/terraform/eks/values/eck-operator-values-system.yaml`, which schedules the
operator on the `system` node group.

4. Verify
```
(base) [dev@DESKTOP-CK48G9R installation]$ kubectl -n elastic-system get sts,deploy,pods
NAME                                READY   AGE
statefulset.apps/elastic-operator   1/1     5m59s

NAME                     READY   STATUS    RESTARTS   AGE
pod/elastic-operator-0   1/1     Running   0          5m59s
(base) [dev@DESKTOP-CK48G9R installation]$ kubectl -n elastic-system get pods --show-labels 
NAME                 READY   STATUS    RESTARTS   AGE     LABELS
elastic-operator-0   1/1     Running   0          6m10s   app.kubernetes.io/instance=elastic-operator,app.kubernetes.io/managed-by=Helm,app.kubernetes.io/name=elastic-operator,app.kubernetes.io/version=3.5.0,apps.kubernetes.io/pod-index=0,controller-revision-hash=elastic-operator-7648bc4c8d,helm.sh/chart=eck-operator-3.5.0,statefulset.kubernetes.io/pod-name=elastic-operator-0,topology.kubernetes.io/region=us-east-2,topology.kubernetes.io/zone=us-east-2b
(base) [dev@DESKTOP-CK48G9R installation]$ kubectl -n elastic-system get pod elastic-operator-0 -o wide
NAME                 READY   STATUS    RESTARTS   AGE     IP           NODE                                      NOMINATED NODE   READINESS GATES
elastic-operator-0   1/1     Running   0          6m32s   10.0.5.252   ip-10-0-5-25.us-east-2.compute.internal   <none>      <none>
```

```
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl api-resources | grep elastic
agents                              agent        agent.k8s.elastic.co/v1alpha1               true         Agent
apmservers                          apm          apm.k8s.elastic.co/v1                       true         ApmServer
autoopsagentpolicies                aop          autoops.k8s.elastic.co/v1alpha1             true         AutoOpsAgentPolicy
elasticsearchautoscalers            esa          autoscaling.k8s.elastic.co/v1alpha1         true         ElasticsearchAutoscaler
beats                               beat         beat.k8s.elastic.co/v1beta1                 true         Beat
elasticsearches                     es           elasticsearch.k8s.elastic.co/v1             true         Elasticsearch
enterprisesearches                  ent          enterprisesearch.k8s.elastic.co/v1          true         EnterpriseSearch
kibanas                             kb           kibana.k8s.elastic.co/v1                    true         Kibana
logstashes                          ls           logstash.k8s.elastic.co/v1alpha1            true         Logstash
elasticmapsservers                  ems          maps.k8s.elastic.co/v1alpha1                true         ElasticMapsServer
packageregistries                   epr          packageregistry.k8s.elastic.co/v1alpha1     true         PackageRegistry
stackconfigpolicies                 scp          stackconfigpolicy.k8s.elastic.co/v1alpha1   true         StackConfigPolicy
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl api-resources | grep elastic.co
agents                              agent        agent.k8s.elastic.co/v1alpha1               true         Agent
apmservers                          apm          apm.k8s.elastic.co/v1                       true         ApmServer
autoopsagentpolicies                aop          autoops.k8s.elastic.co/v1alpha1             true         AutoOpsAgentPolicy
elasticsearchautoscalers            esa          autoscaling.k8s.elastic.co/v1alpha1         true         ElasticsearchAutoscaler
beats                               beat         beat.k8s.elastic.co/v1beta1                 true         Beat
elasticsearches                     es           elasticsearch.k8s.elastic.co/v1             true         Elasticsearch
enterprisesearches                  ent          enterprisesearch.k8s.elastic.co/v1          true         EnterpriseSearch
kibanas                             kb           kibana.k8s.elastic.co/v1                    true         Kibana
logstashes                          ls           logstash.k8s.elastic.co/v1alpha1            true         Logstash
elasticmapsservers                  ems          maps.k8s.elastic.co/v1alpha1                true         ElasticMapsServer
packageregistries                   epr          packageregistry.k8s.elastic.co/v1alpha1     true         PackageRegistry
stackconfigpolicies                 scp          stackconfigpolicy.k8s.elastic.co/v1alpha1   true         StackConfigPolicy
```

## Deploy ECK Stack (via Helm)
1. Add/Update Elastic Helm Repo
```
helm repo add elastic https://helm.elastic.co
helm repo update
```

2. Configure ECK Stack
- Configure nodeSets with associated node roles and counts
- Configure resources, nodeAffinity and volumeClaimTemplates according to existing node labels and existing csi

3. Install ECK Stack
```
helm install eck-stack-small elastic/eck-stack -f ../../iac/terraform/eks/values/eck-stack-values-eks-demo-small.yaml -n elastic-stack --create-namespace
```

For the EKS cluster with separate Elasticsearch master and hot data node
groups, use the medium flavor values file as the only values file:

```
helm install eck-stack-medium elastic/eck-stack \
  -f ../../iac/terraform/eks/values/eck-stack-values-eks-demo-medium.yaml \
  -n elastic-stack --create-namespace
```

The medium flavor schedules master nodes on `elasticsearch-role=master` nodes
and hot data nodes on
`elasticsearch-role=hot` nodes. Both labels are created by the Terraform EKS
configuration.

4. Verify Running services
```
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl -n elastic-stack get svc,deploy,sts,pods
NAME                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/eck-stack-small-eck-kibana-kb-http   ClusterIP   172.20.196.2    <none>        5601/TCP   27m
service/elasticsearch-es-default             ClusterIP   None            <none>        9200/TCP   27m
service/elasticsearch-es-http                ClusterIP   172.20.60.103   <none>        9200/TCP   27m
service/elasticsearch-es-internal-http       ClusterIP   172.20.7.40     <none>        9200/TCP   27m
service/elasticsearch-es-transport           ClusterIP   None            <none>        9300/TCP   27m

NAME                                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/eck-stack-small-eck-kibana-kb   2/2     2            2           27m

NAME                                        READY   AGE
statefulset.apps/elasticsearch-es-default   3/3     27m

NAME                                                 READY   STATUS        RESTARTS   AGE
pod/eck-stack-small-eck-kibana-kb-64bcfbf479-hjdhg   1/1     Running       0          27m
pod/eck-stack-small-eck-kibana-kb-64bcfbf479-rchqx   0/1     Terminating   0          11m
pod/eck-stack-small-eck-kibana-kb-794f754c54-2hb7j   1/1     Running       0          11m
pod/eck-stack-small-eck-kibana-kb-794f754c54-nlj5q   0/1     Running       0          17s
pod/elasticsearch-es-default-0                       1/1     Running       0          3m24s
pod/elasticsearch-es-default-1                       1/1     Running       0          3m24s
pod/elasticsearch-es-default-2                       1/1     Running       0          3m24s
```

```
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl -n elastic-stack get sc,pvc
NAME                              PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
storageclass.storage.k8s.io/gp2   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  45h

NAME                                                                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/elasticsearch-data-elasticsearch-es-default-0   Bound    pvc-e64b7baf-6663-4cab-babb-8a1259c2736b   10Gi       RWO            gp2            <unset>                 36m
persistentvolumeclaim/elasticsearch-data-elasticsearch-es-default-1   Bound    pvc-6c251edb-e185-4ef1-a17c-ad5adbbb45bb   10Gi       RWO            gp2            <unset>                 36m
persistentvolumeclaim/elasticsearch-data-elasticsearch-es-default-2   Bound    pvc-f61ec8f9-0726-4959-bed0-edc31f483a1a   10Gi       RWO            gp2            <unset>                 36m
```

```
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl -n elastic-stack get kibana
NAME                         HEALTH   NODES   VERSION   AGE
eck-stack-small-eck-kibana   green    2       9.5.0     29m
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl -n elastic-stack get kibana
NAME                         HEALTH   NODES   VERSION   AGE
eck-stack-small-eck-kibana   green    2       9.5.0     29m
```

```
(base) [dev@DESKTOP-CK48G9R install-config]$ kubectl get elastic -n elastic-stack -l "app.kubernetes.io/instance"=eck-stack-small
NAME                                                 HEALTH   AVAILABLE   EXPECTED   TYPE         VERSION   AGE
beat.beat.k8s.elastic.co/eck-stack-small-eck-beats   yellow   3           5          metricbeat   9.5.0     64s

NAME                                                       HEALTH    NODES   VERSION   PHASE             AGE
elasticsearch.elasticsearch.k8s.elastic.co/elasticsearch   unknown           9.5.0     ApplyingChanges   20s

NAME                                  HEALTH   NODES   VERSION   AGE
kibana.kibana.k8s.elastic.co/kibana   red              9.5.0     65s
```
