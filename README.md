<p align="center">
  <img src="./docs/assets/dungeon-banner.png" height="180" alt="Dungeon">
</p>

> K8s is not the final dungeon, it's the legendary drop we'll need to get through it!

This repository seeks to be the source of truth regarding the active state of my Kubernetes cluster "Dungeon" and my Proxmox Cluster "Ad_Arbitorium". All system state, automation routines, and backup strategies should be declared within this repository.

> Maintained by [SoFMeRight](https://github.com/sofmeright) for [PrPlanIT](https://prplanit.com) — Real world results for your real world expectations. <br>

<!-- sf:badges:start -->
[![pipeline](https://raw.githubusercontent.com/SoFMeRight/dungeon/main/.stagefreight/scribe/pipeline.svg)](https://gitlab.prplanit.com/SoFMeRight/dungeon/-/pipelines) [![Last Commit](https://img.shields.io/github/last-commit/SoFMeRight/dungeon)](https://github.com/SoFMeRight/dungeon/commits) [![StageFreight](https://img.shields.io/badge/StageFreight-0.9.2--dev+ad99951-310937?logo=readthedocs&logoColor=white)](https://stagefreight.prplanit.com)
<!-- sf:badges:end -->

<!-- sf:tooling:start -->
[![managed by StageFreight](https://img.shields.io/badge/managed_by_StageFreight-0.9.2--dev+177b6a5-310937)](https://github.com/sofmeright/stagefreight) [![pipeline](https://gitlab.prplanit.com/SoFMeRight/dungeon/-/raw/main/.stagefreight/scribe/pipeline.svg)](https://gitlab.prplanit.com/SoFMeRight/dungeon/-/pipelines) [![Security](https://img.shields.io/badge/Security-report-4B275F)](https://gitlab.prplanit.com/SoFMeRight/dungeon/-/blob/main/docs/container-security-audit.md)
<!-- sf:tooling:end -->

<!-- sf:stack:start -->
[![Ansible](https://img.shields.io/badge/Ansible-automation-EE0000?logo=ansible&logoColor=white)](https://github.com/SoFMeRight/dungeon/blob/main/ansible) [![Kubernetes](https://img.shields.io/badge/Kubernetes-k8s-326CE5?logo=kubernetes&logoColor=white)](https://github.com/SoFMeRight/dungeon/blob/main/fluxcd) [![FluxCD](https://img.shields.io/badge/FluxCD-gitops-5468FF?logo=flux&logoColor=white)](https://github.com/SoFMeRight/dungeon/blob/main/fluxcd) [![Applications](https://img.shields.io/badge/Applications-%7Binventory.dungeon.count%7D-0F1689?logo=kubernetes&logoColor=white)](https://github.com/SoFMeRight/dungeon/blob/main/docs/Apps_&_Services-Overview.md) [![Compose](https://img.shields.io/badge/Compose-stacks-2496ED?logo=docker&logoColor=white)](https://github.com/SoFMeRight/dungeon/blob/main/docker)
<!-- sf:stack:end -->

---

## 📂 Infrastructure as Code (IaC)
|                                                |                                                                 |
| ---------------------------------------------  | --------------------------------------------------------------- |
| 🧪 **Ansible Playbooks**                      | [Located in the `ansible/*/` directory](ansible/)                |
| 🐧 **Ansible Inventory**                      | [Located at `ansible/inventory`](ansible/inventory)             |
| 💫 **FluxCD Configuration**                   | [Located at the `fluxcd` directory](fluxcd)                      |
| 📦 **Docker Compose Deployments**             | [Stored in the `docker-compose` directory](docker-compose)       |
| 🕸️ **NGINX Proxy Configurations**             | [Stored in the `nginx-extras` directory](nginx-extras)           |
| ⚙️ **General Configuration Files**            | [Stored in the `fs` directory](fs)                               |
| 💾 **Backup Automation & Recovery Scripts**   |                                                                  |

> Where possible, configuration is version-controlled. In some cases (e.g., Docker volumes or secrets), data resides in protected resources or local mounts.

### Frequently Requested Info

|                     |                                                                                                                   |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 📦 Docker Stacks    | [A (stale) generated list of Docker deployments (I'm near exclusively k8s now...)](./docker-compose/README.md)    |
| 🖥️ Hardware         | [In-depth details regarding most of the hardware in this lab.](./docs/Hardware.md)                                |
| 📦 Kubernetes Pods  | [A pipeline generated list of applications I have deployed within kubernetes](./docs/Apps_&_Services-Overview.md) |

## Related Projects
|                                                           |                                                                                        |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| [Ansible](https://github.com/HomeLabHD/ansible)           | Lightweight Alpine-based Ansible image with Windows support and community collections  |
| [StageFreight](https://github.com/PrPlanIT/StageFreight)  | A declarative lifecycle runtime — GitOps, Kubernetes, Docker & CI from one manifest    |

---

## 📅 Backup Schedule

Our peak hours are typically 6:00AM – 10:00PM PST. Backups are scheduled to minimize risk during these times.

| Day           | Time  | Task                                             |
| ------------- | ----- | ------------------------------------------------ |
| Daily         | 18:00 | Dungeon (K8s) Backup via Velero                  |
| Mon, Fri      | 22:00 | NAS & PBS → local-zfs backup                     |
| Tue, Thu, Fri | 23:00 | All other core/essential VMs → Flashy-Fuscia-SSD |

## 🖥️ Hardware Overview

### Ad Arbitorium: Proxmox VE Cluster

| Host           | CPU                                         | RAM                |
| -------------- | ------------------------------------------- | ------------------ |
| 🥑 Avocado     | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🎍 Bamboo      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 96GB (6×16GB ECC)  |
| 🌌 Cosmos      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🐉 Dragonfruit | AMD Ryzen 7 2700X (8C/16T) 3.7–4.35GHz      | 64GB (2×32GB ECC)  |
| 🍆 Eggplant    | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 128GB (16×8GB ECC) |

####  Unclustered Hosts

| Host               | CPU                                         | RAM                | Purpose                                                                                             |
| ------------------ | ------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------- |
| 🪲 leaf-cutter     | Intel i7-4720HQ (8 threads @ 3.6GHz)        | 16GB (2×8GB DDR3) | This node runs critical automation if the cluster fails. Think of it as "ant-parade's stunt double." |

---

## 🧱 Core Workloads
- PVE – Bare metal Proxmox hosts
- Ubuntu 24.04 + Docker – Most VMs run containers (including GPU workloads)
- FusionPBX – VOIP System
- Kubernetes – 5-node cluster
- PBS (Proxmox Backup Server)
- Portainer – Jump node: harbormaster
- Shinobi – CCTV & surveillance
- TrueNAS
- Windows Server – Active Directory 3-node forest

## Dashboards and UIs
- Weave-Gitops
- FreeLens
- Portainer

## 🌐 Networking

| Technology           | Purpose Used                                                         |
| -------------------- | -------------------------------------------------------------------- |
| pfSense              | 2 VMs running on Avocado & Bamboo Highly Available routing via CARP, Dual-stack IPv4/6, BGP. (future: evaluate OPNsense again) |
| OSPFv6               | Proxmox/Ceph private/internal network                                |
| BGP                  | Kubernetes Load Balancers (Cilium peers with pfsense).               |
| kube-vip             | Kubernetes API Load balancing                                        |
| Istio                | The chosen cluster mesh.                                             |
| AdGuardHome          | DNS Server & Highly Available with 1 master and 1 replica, likely migrating to Technitium  or Gravity soon. |

## 🧠 Observability & Monitoring

| Technology           | Purpose Used                                                                 |
| -------------------- | ---------------------------------------------------------------------------- |
| Grafana              | Amazing dashboard for Metrics, Logs, Tracing, Security, many other usecases! |
| Loki                 | Logging, collection and aggregation                                          |
| Victoria Metrics     | Metrics                                                                      |
| Crowdsec             | Open Source Crowd Based Threat Detection and Prevention System, with pfsense & other integrations |
| Beszel               | alternative option for viewing some metrics                                  |
| Wazuh                | SIEM, I haven't had the chance to get as familiar with this one              |

## Reverse Proxies:

- cell-membrane, phloem, and xylem handle NGINX proxy duties
> Internal domains like *.pcfae.com live inside xylem (no external exposure)

## VPN / Remote Access Tools
| Technology           | Purpose Used                                                         |
| -------------------- | -------------------------------------------------------------------- |
| Moonlight/Sunshine   | Remote Desktop. Sunshine is the Server, Moonlight is the Client. Gaming friendly and they package clients for most every device. |
| netbird              |                                                      |
| Rustdesk             | Its basically self hosted AnyDesk. It works. |
| Tactical-RMM         | Full featured Remote Monitoring & Management system. |

---

## ⚙️ Automations & Tooling

### 🛠️ Primary Automation: Ansible

We use [Ansible](https://www.ansible.com/) with playbooks stored in this repo and executed via:

- 🔐 [Ansible Semaphore](https://ansible-semaphore.com/) — for web-based job triggering
- 🐳 GitLab CI/CD Components — for automated GitOps-style deployments
- 💡 *Ideas in progress*: OliveTin, or Cronguru for task selection.

### 🗄️ Repository Recovery

> **ant-parade & leaf-cutter** to the rescue! 🐜

If the cluster fails, we can recover from a local repo clone on `leaf-cutter`:

```bash
docker run --rm \
    -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
    -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private:ro \
    cr.pcfae.com/prplanit/ansible:2.18.6 \
  ansible-playbook --private-key /root/.ssh/id_rsa \
  -i /srv/gitops/ad-arbitorium-private/ansible/inventory \
  /srv/gitops/ad-arbitorium-private/ansible/infrastructure/qemu-guest-agent-debian.yaml
```
##### WinRM Example:

```bash
docker run --rm \
    -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
    -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private:ro \
    -v ./playbook.yaml:/root/playbook.yaml:ro \
    cr.pcfae.com/prplanit/ansible:2.18.6 \
  ansible-playbook \
    --private-key /root/.ssh/id_rsa \
    -i /srv/gitops/ad-arbitorium-private/ansible/inventory \
    /root/playbook.yaml \
    -e ansible_windows_password="${WINDOWS_ANSIBLE_PASSWORD}"
```

## 🤓 Want to contribute or improve the stack?
This is a private lab, but feedback, discussion, and memes are always welcome. ✉️

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T41IT163)

## ⚠️ Disclaimer

> The code, images, and infrastructure templates herein (the "Software") are provided as-is and as-absurd—without warranties, guarantees, or even friendly nudges. <br>
The authors accept no liability if this repo makes your cluster self-aware, breaks your ankle (metaphorically or otherwise), or causes irreversible YAML-induced burnout.  <br>
We take no responsibility if running this setup somehow: launches a container into orbit, bricks your homelab, or awakens a long-dormant AI from /dev/null. Use at your own risk. <br>
If it works, thank the open-source gods. If it doesn't, well... you probably learned something.
