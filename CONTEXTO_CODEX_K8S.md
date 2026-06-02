# Contexto para continuar el laboratorio Kubernetes + Spring Boot

Estudiante: Wilson Steven Karmelt Heredia Rodriguez  
Codigo: 202021647  
Proyecto: `usuarios` Spring Boot + PostgreSQL + Kubernetes

## Arquitectura

- `master`: control-plane Kubernetes.
- `node1`: worker.
- `node2`: worker.
- `db`: VM externa con PostgreSQL y PgBouncer.
- App: `usuarios-api`, endpoint principal `/api/usuarios`.
- DB externa por PgBouncer: puerto `6432`.
- Pod CIDR correcto: `10.244.0.0/16`.
- CNI: Calico.
- Exposicion externa: Nginx Ingress Controller por NodePort.

## Redes usadas

Casa:

```text
master  192.168.40.10
node1   192.168.40.11
node2   192.168.40.12
db      192.168.40.13
```

Universidad:

```text
master  192.168.137.10
node1   192.168.137.11
node2   192.168.137.12
db      192.168.137.13
```

La interfaz de VirtualBox usada fue `enp0s8`.

## Problemas encontrados y soluciones

1. Netplan tenia dos archivos activos:
   - `00-installer-config.yaml` con `192.168.40.x`.
   - `99-*-static.yaml` con `192.168.137.x`.
   Esto produjo doble IP y rutas default duplicadas.
   Solucion: mover YAMLs viejos a disabled y dejar solo `99-ROLE-static.yaml`.

2. `kubectl` apuntaba a la IP vieja:
   - `https://192.168.40.10:6443`
   Solucion: reemplazar en `/etc/kubernetes/*.conf` y copiar `/etc/kubernetes/admin.conf` a `~/.kube/config`.

3. El API Server levanto, pero fallo certificado:
   - certificado valido para `192.168.40.10`, no para `192.168.137.10`.
   Solucion:
   ```bash
   sudo rm /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
   sudo kubeadm init phase certs apiserver --apiserver-advertise-address=NUEVA_IP_MASTER
   sudo systemctl restart kubelet
   ```

4. `kube-scheduler` quedo `0/1` con:
   - `sched-handler-sync failed`
   Solucion: mover temporalmente el manifest y devolverlo para recrear el static pod.

5. `kube-proxy` quedo roto porque su ConfigMap apuntaba al master viejo.
   Solucion: reemplazar IP vieja por nueva en `cm/kube-proxy` y reiniciar DaemonSet.

6. `node1` y `node2` quedaron `NotReady` hasta corregir:
   - `/etc/kubernetes/kubelet.conf`
   - `/etc/kubernetes/bootstrap-kubelet.conf`
   - `/etc/default/kubelet` con `KUBELET_EXTRA_ARGS=--node-ip=IP_DEL_NODO`

7. PgBouncer en `db` seguia escuchando la IP vieja.
   Solucion: reemplazar IP en `/etc/pgbouncer/pgbouncer.ini` y reiniciar `pgbouncer`.

8. La app quedo sin endpoints porque los pods estaban `0/1`.
   Causa frecuente: Spring Boot tarda en arrancar y las probes lo matan.
   Solucion aplicada/sugerida:
   ```bash
   kubectl -n usuarios patch deployment usuarios-api --type='json' -p='[
     {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":120},
     {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":180},
     {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":10},
     {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":10},
     {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":12},
     {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":6}
   ]'
   ```

## Scripts importantes

- `scripts/lab-ips.env`: red de casa `192.168.40.x`.
- `scripts/uptc-ips.env`: red universidad `192.168.137.x`.
- `scripts/vm-first-boot.sh`: configura hostname, hosts, netplan, SSH y kubelet node-ip.
- `scripts/k8s-after-ip-change.sh`: corregir Kubernetes despues de cambiar IP del master.
- `scripts/db-after-ip-change.sh`: corregir PgBouncer/PostgreSQL despues de cambiar IP de DB.
- `scripts/seed-usuarios.sh`: insertar usuarios de prueba.

## Flujo para cambiar de casa a universidad

En cada VM:

```bash
cd /home/master/scripts
sudo bash ./vm-first-boot.sh master enp0s8 ./uptc-ips.env   # solo en master
sudo bash ./vm-first-boot.sh node1  enp0s8 ./uptc-ips.env   # solo en node1
sudo bash ./vm-first-boot.sh node2  enp0s8 ./uptc-ips.env   # solo en node2
sudo bash ./vm-first-boot.sh db     enp0s8 ./uptc-ips.env   # solo en db
sudo reboot
```

En master despues de reiniciar:

```bash
cd /home/master/scripts
sudo bash ./k8s-after-ip-change.sh ./uptc-ips.env 192.168.40.10
```

En db despues de reiniciar:

```bash
cd /home/master/scripts
sudo bash ./db-after-ip-change.sh ./uptc-ips.env 192.168.40.13
```

En node1:

```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.137.11' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart containerd kubelet
```

En node2:

```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.137.12' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart containerd kubelet
```

## Flujo para volver de universidad a casa

Mismo flujo, pero usando `lab-ips.env` y las IP viejas:

```bash
sudo bash ./vm-first-boot.sh master enp0s8 ./lab-ips.env
sudo bash ./k8s-after-ip-change.sh ./lab-ips.env 192.168.137.10
sudo bash ./db-after-ip-change.sh ./lab-ips.env 192.168.137.13
```

## Verificacion final

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n usuarios get pods -o wide
kubectl -n usuarios get endpoints usuarios-api -o wide
nc -vz DB_IP 6432
curl http://MASTER_IP:31185/api/usuarios
curl http://MASTER_IP:30784/api/usuarios
for i in {1..10}; do curl -s http://MASTER_IP:30784/api/usuarios; echo; done
```

Si `usuarios-api` no tiene endpoints, revisar que los pods esten `1/1`.
