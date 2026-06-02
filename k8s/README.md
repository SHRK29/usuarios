# Taller Kubernetes + Spring Boot + PostgreSQL externo

Esta carpeta despliega la API `usuarios` en Kubernetes con 4 pods Spring Boot, balanceados por un `Service` e ingreso por Nginx Ingress. La base de datos queda fuera del cluster en la VM `db`, y Kubernetes entra a PgBouncer usando el servicio interno `postgres-service`.

## Arquitectura usada

- `master`: `192.168.40.10`
- `node1`: `192.168.40.11`
- `node2`: `192.168.40.12`
- `db`: `192.168.40.13`
- PostgreSQL en `db:5432`
- PgBouncer en `db:6432`
- `usuarios-api`: Deployment con 4 replicas Spring Boot.
- `postgres-service`: Service + EndpointSlice que apuntan a `192.168.40.13:6432`.
- `usuarios-api`: Service `ClusterIP` para balancear pods.
- `usuarios-api` Ingress: entrada HTTP por Nginx Ingress.
- Red de pods recomendada: `10.244.0.0/16`.

Importante: no uses `192.168.0.0/16` como red de pods si tus VMs estan en `192.168.40.0/24`. Ese rango se solapa y hace que los pods no puedan llegar bien a la VM `db`.

## 0. Corregir IPs de Kubernetes

En cada VM fija el `node-ip` de kubelet.

En `master`:

```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.40.10' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

En `node1`:

```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.40.11' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

En `node2`:

```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.40.12' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

Verifica desde `master`:

```bash
kubectl get nodes -o wide
```

Debe aparecer `INTERNAL-IP` con `192.168.40.10`, `192.168.40.11` y `192.168.40.12`.

Reinicia Calico:

```bash
kubectl -n kube-system rollout restart daemonset/calico-node
kubectl -n kube-system get pods -o wide
```

Si el cluster fue creado con `--pod-network-cidr=192.168.0.0/16`, recrealo con:

```bash
sudo kubeadm init --apiserver-advertise-address=192.168.40.10 --pod-network-cidr=10.244.0.0/16
```

Y aplica Calico cambiando su pool a `10.244.0.0/16`.

## 1. Preparar la VM db

En la VM `db`, verifica que tenga la IP correcta:

```bash
ip -4 addr
```

Debe aparecer `192.168.40.13`.

Ejecuta PostgreSQL + PgBouncer:

```bash
chmod +x scripts/db-ubuntu-pgbouncer.sh
DB_IP=192.168.40.13 DB_PASSWORD=postgres ./scripts/db-ubuntu-pgbouncer.sh
```

Si PgBouncer falla, revisa:

```bash
systemctl status pgbouncer --no-pager
journalctl -xeu pgbouncer.service --no-pager | tail -80
```

Verifica desde `master`:

```bash
nc -vz 192.168.40.13 6432
psql "host=192.168.40.13 port=6432 dbname=usuariosdb user=postgres password=postgres"
```

## 2. Preparar la imagen

En la maquina donde tengas Docker:

```bash
docker build -t usuarios-api:1.0.0 .
```

Si usas un registry:

```bash
docker tag usuarios-api:1.0.0 TU_REGISTRY/usuarios-api:1.0.0
docker push TU_REGISTRY/usuarios-api:1.0.0
```

Luego cambia `image: usuarios-api:1.0.0` en `04-deployment.yaml`.

Si no usas registry y tienes containerd en los nodos:

```bash
docker save usuarios-api:1.0.0 -o usuarios-api.tar
sudo ctr -n k8s.io images import usuarios-api.tar
```

Repite el import en `node1` y `node2`.

## 3. Revisar IP de base de datos

El archivo `03-postgres-external-service.yaml` debe apuntar a la VM `db`:

```yaml
endpoints:
  - addresses:
      - "192.168.40.13"
```

Tambien revisa usuario y clave en `02-secret.yaml`.

## 4. Instalar Nginx Ingress Controller

Si no lo tienes instalado:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/baremetal/deploy.yaml
```

En bare metal normalmente se expone como `NodePort`. Puedes probar con la IP de cualquier nodo y el puerto asignado:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

## 5. Desplegar la app

```bash
kubectl apply -f k8s/
kubectl -n usuarios get pods -o wide
kubectl -n usuarios get svc,endpointslice,ingress
```

## 6. Pruebas

Crear usuario:

```bash
curl -X POST http://IP_O_HOST_DEL_INGRESS/api/usuarios \
  -H "Content-Type: application/json" \
  -d '{"name":"Ana Perez","username":"ana","email":"ana@example.com"}'
```

Listar usuarios:

```bash
curl http://IP_O_HOST_DEL_INGRESS/api/usuarios
```

El JSON debe mostrar `ipAddress` y `instanceTag`. `instanceTag` queda con el nombre del pod, asi puedes evidenciar el balanceo entre replicas.

## 7. Escalar

```bash
kubectl -n usuarios scale deployment usuarios-api --replicas=4
kubectl -n usuarios get pods -o wide
```

## 8. Diagnostico rapido

```bash
kubectl -n usuarios describe pod -l app=usuarios-api
kubectl -n usuarios logs -l app=usuarios-api --tail=100
kubectl -n usuarios exec deploy/usuarios-api -- printenv | grep DB_
```

Si los pods quedan `Ready 0/1`, revisa primero que PgBouncer responda en `192.168.40.13:6432` y que PostgreSQL permita conexiones desde la red de pods. No agregues `currentSchema=usuarios_schema` al JDBC cuando uses PgBouncer, porque PgBouncer puede rechazar el parametro startup `search_path`; la app ya fija el schema con Hibernate.

## 9. Red UPTC 192.168.137.x

Para preparar las VMs desde la consola de VirtualBox y luego entrar por SSH/MobaXterm, copia la carpeta `scripts/` a cada VM y ejecuta segun el rol.

IPs propuestas:

```text
master: 192.168.137.10
node1:  192.168.137.11
node2:  192.168.137.12
db:     192.168.137.13
```

En cada VM:

```bash
sudo ./scripts/vm-first-boot.sh master enp0s3 ./scripts/uptc-ips.env
sudo ./scripts/vm-first-boot.sh node1 enp0s3 ./scripts/uptc-ips.env
sudo ./scripts/vm-first-boot.sh node2 enp0s3 ./scripts/uptc-ips.env
sudo ./scripts/vm-first-boot.sh db enp0s3 ./scripts/uptc-ips.env
```

Ejecuta solo el comando que corresponde a esa VM. Si tu interfaz no se llama `enp0s3`, revisa:

```bash
ip -o link show
```

Luego entra desde MobaXterm:

```bash
ssh master@192.168.137.10
ssh master@192.168.137.11
ssh master@192.168.137.12
ssh master@192.168.137.13
```

Al recrear Kubernetes en esa red, usa:

```bash
sudo kubeadm init --apiserver-advertise-address=192.168.137.10 --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=Mem
```

La DB debe quedar en:

```bash
DB_IP=192.168.137.13 DB_PASSWORD=postgres ./scripts/db-ubuntu-pgbouncer.sh
```

Y la app:

```bash
kubectl -n usuarios set env deployment/usuarios-api DB_URL="jdbc:postgresql://192.168.137.13:6432/usuariosdb"
```

## 10. Cargar 50 Usuarios

Con la API expuesta por Nginx Ingress:

```bash
chmod +x scripts/seed-usuarios.sh
./scripts/seed-usuarios.sh http://192.168.40.10:30784 50
```

En UPTC, si el Ingress queda con el mismo puerto `30784`:

```bash
./scripts/seed-usuarios.sh http://192.168.137.10:30784 50
```
