# Hardware Inventory

## Storage Drives

### Ceph NVMe Storage - Samsung PM1725 / F320 Series

**Total**: 6x Samsung 3.2TB NVMe PCIe 3.0 x8 Enterprise SSDs (mixed models)

#### Drive Specifications
- **Models**:
  - 2x Samsung PM1725 HHHL (MZPLK3T2HCJL MZ-PLK3T2A XTTR5)
  - 1x Samsung PM1725 (MZPLK3T2HCJL-0003)
  - 1x Samsung F320 NVMe (MZPLK3T2HCJL-000U4) - Oracle branded
  - 2x Samsung F320 NVMe (MZ-PLK3T20)
- **Capacity**: 3.2TB per drive (19.2TB total raw)
- **Interface**: PCIe 3.0 x8 NVMe
- **Form Factor**: HHHL (Half-Height, Half-Length) / Standard NVMe
- **Performance** (typical):
  - Sequential Read: ~6,500 MB/s
  - Sequential Write: ~3,200 MB/s
  - Random Read IOPS: ~1,000,000 IOPS (4KB)
  - Random Write IOPS: ~120,000 IOPS (4KB)
- **Endurance**: Enterprise-grade
- **Use Case**: Ceph OSD storage for dungeon cluster

#### Purchase History

| Order Date | Quantity | Model/SKU | Cost | Status | Delivery |
|------------|----------|-----------|------|--------|----------|
| Oct 13, 2025 | 2 | SAMSUNG PM1725 HHHL MZPLK3T2HCJL MZ-PLK3T2A XTTR5 | $242.22 | Awaiting Shipment | Est. Oct 16-20 |
| Apr 6, 2025 | 1 | SAMSUNG PM1725 3.2TB MZPLK3T2HCJL-0003 | $176.15 | Delivered | Apr 12, 2025 |
| Oct 26, 2024 | 1 | Oracle 7317693 3.2TB (Samsung MZPLK3T2HCJL-000U4) | $167.63 | Delivered | Nov 1, 2024 |
| Jun 20, 2024 | 2 | Samsung 3.2TB V-NAND F320 NVMe MZ-PLK3T20 | $314.78 | Delivered | Jun 28, 2024 |

**Total Investment**: $900.78 for 19.2TB enterprise NVMe storage ($47/TB)

#### Deployment Plan
- **Current Configuration**: size=4, min_size=2 (4 full replicas) - running out of space
- **Target Configuration**: size=3, min_size=2 (3 full replicas) with 6 drives
- **Distribution**: 6 drives across 3 of 5 Proxmox nodes (2 drives per Proxmox host)
- **Usable Capacity**: ~6.4TB (19.2TB / 3 replicas)
- **Failure Tolerance**: 2 drive failures (with size=3)
- **Expected Performance**: 40-60% improvement over previous 4-drive setup

## Proxmox Cluster Nodes

The datacenter is powered by Proxmox VE and consists of five clustered nodes:

| Host           | CPU                                         | RAM                | GPU                        | Notes |
| -------------- | ------------------------------------------- | ------------------ | -------------------------- | ----- |
| 🥑 Avocado     | 2× Xeon E5-2618L v4 (20C, SMT off) 2.20–3.20 GHz | 320GB (10×32GB ECC) | NVIDIA RTX A2000 12GB      | Hosts pfSense HA primary |
| 🎍 Bamboo      | 2× Xeon E5-2618L v4 (20C, SMT off) 2.20–3.20 GHz | 320GB (10×32GB ECC) | -                          | Hosts pfSense HA secondary |
| 🌌 Cosmos      | 2× Xeon E5-2618L v4 (20C, SMT off) 2.20–3.20 GHz | 320GB (10×32GB ECC) | -                          | |
| 🐉 Dragonfruit | AMD Ryzen 7 2700X (8C/16T) 3.7–4.35GHz      | 64GB (2×32GB ECC)  | NVIDIA RTX 3080 Ti         | |
| 🍆 Eggplant    | 2× Xeon E5-2618L v4 (20C, SMT off) 2.20–3.20 GHz | 224GB (6×16GB + 16×8GB ECC) | -                          | |

96 threads and 1.2 TiB (1,248GB) of RAM across the cluster. SMT is off on the Xeon hosts (see [proxmox-cpu-configuration.md](./proxmox-cpu-configuration.md)).

### Kubernetes VMs (Hosted on Proxmox)

#### Control Plane Nodes (dungeon-map-*)
- dungeon-map-001: 172.22.144.150 / fc00:f1:ada:1043:1ac3::150
- dungeon-map-002: 172.22.144.151 / fc00:f1:ada:1043:1ac3::151
- dungeon-map-003: 172.22.144.152 / fc00:f1:ada:1043:1ac3::152
- dungeon-map-004: 172.22.144.153 / fc00:f1:ada:1043:1ac3::153
- dungeon-map-005: 172.22.144.154 / fc00:f1:ada:1043:1ac3::154
- **VIP**: 172.22.144.105 / fc00:f1:ada:1043:1ac3::105

#### Worker Nodes (dungeon-chest-*)
- dungeon-chest-001: 172.22.144.170 / fc00:f1:ada:1043:1ac3::170
- dungeon-chest-002: 172.22.144.171 / fc00:f1:ada:1043:1ac3::171
- dungeon-chest-003: 172.22.144.172 / fc00:f1:ada:1043:1ac3::172
- dungeon-chest-004: 172.22.144.173 / fc00:f1:ada:1043:1ac3::173
- dungeon-chest-005: 172.22.144.174 / fc00:f1:ada:1043:1ac3::174

### 🥑 Avocado - Detailed Component List

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Chassis** | SuperChassis 826BE1C-R920LPB | May 10, 2024 | $630.87 | 2U 12 Bay, SAS3 12gbps |
| **CPU** | 2× Intel Xeon E5-2618L v4 | - | - | 20 cores, SMT off |
| **PSU** | 2× Supermicro PWS-920P-SQ | - | - | Came with chassis, 920W 80+ Platinum |
| **RAM** | 10× Samsung M386A4G40DM0-CPB | - | - | 32GB DDR4-2133 ECC LRDIMM, 320GB, 10 of 16 slots |
| **GPU** | NVIDIA RTX A2000 12GB | Jul 1, 2024 | $440.40 | Warranty through 03/2025 |
| **NIC** | Silicom PE310G4SPI9L-XR-CX3 | Nov 9, 2024 | $40.78 | Quad Port 10GB SFP+ |
| **NIC Bracket** | Low Bracket for PE310G4SPI9L | Nov 13, 2024 | $4.35 | |
| **Ceph SSD** | Samsung F320 NVMe 3.2TB (MZ-PLK3T20) | Jun 20, 2024 | $157.39 | PCIe 3.0 x8 |

### 🎍 Bamboo - Detailed Component List

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Chassis** | Supermicro CSE-826 | Feb 12, 2022 | $275.00 | 2U 12 Bay (no rear 2.5" SSD slots) |
| **CPU** | 2× Intel Xeon E5-2618L v4 | - | - | 20 cores, SMT off |
| **CPU Cooler** | Supermicro SNK-P0048PS | Dec 30, 2024 | $12.06 | Screw down heatsink |
| **Motherboard** | Supermicro X10DRH-iT | Dec 31, 2024 | $131.02 | Dual LGA2011-3, onboard 10GbE |
| **RAM** | 10× Samsung M386A4G40DM0-CPB | - | - | 32GB DDR4-2133 ECC LRDIMM, 320GB, 10 of 16 slots |
| **PSU** | 2× Supermicro PWS-920P-SQ | Nov 9, 2023 | $75.18 | 920W 80+ Platinum |
| **HBA** | LSI Lenovo 9240-8i | Nov 2, 2024 | $19.81 | 8-port SAS/SATA controller |
| **NIC** | Silicom PE310G4SPI9L-XR-CX3 | Nov 9, 2024 | $40.78 | Quad Port 10GB SFP+ |
| **NIC Bracket** | Low Bracket for PE310G4SPI9L | Nov 13, 2024 | $4.35 | |
| **Ceph SSD** | Oracle 7317693 3.2TB (Samsung F320) | Oct 26, 2024 | $167.63 | MZPLK3T2HCJL-000U4 |
| **SSD Bracket** | Low Profile for PM1725/F320 | Nov 26, 2024 | $2.75 | |
| **Backplane** | Supermicro CSE-826/847 | May 23, 2024 | $71.57 | 2U 6Gbps SAS-2/SATA, 12 bay 3.5" |

### 🌌 Cosmos - Detailed Component List

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Chassis** | SuperChassis 826BE1C-R920LPB | Jan 4, 2025 | $448.77 | 2U 12 Bay, SAS3 12gbps |
| **RAM** | 8× Samsung M386A4G40DM0-CPB + 2× SK Hynix HMA84GL7MMR4N-TF | - | - | 32GB DDR4-2133 ECC LRDIMM, 320GB, 10 of 16 slots |
| **NIC** | Intel X520-DA2 | Sep 21, 2023 | $24.21 | Dual Port SFP+, Low Profile |
| **Ceph SSD** | Samsung F320 NVMe 3.2TB (MZ-PLK3T20) | Jun 20, 2024 | $157.39 | PCIe 3.0 x8 |

### 🐉 Dragonfruit - Detailed Component List

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Chassis** | Rosewill RSV-L4000U | Sep 4, 2024 | $209.18 | 4U rackmount, up to 8× 3.5" HDD |
| **Rails** | iStarUSA TC-RAIL-26 | Jul 22, 2024 | $44.49 | 26" sliding rails |
| **CPU** | AMD Ryzen 7 2700X | Oct 27, 2018 | $309.89 | 8C/16T, with Wraith Prism cooler |
| **Motherboard** | ASUS Prime X370-Pro | Oct 21, 2018 | $79.21 | AM4, DDR4, Aura Sync RGB |
| **RAM** | 2× Micron 18ASF4G72AZ-3G2F1 | - | - | 32GB DDR4-3200 ECC UDIMM, 64GB, 2 of 4 slots |
| **GPU** | NVIDIA RTX 3080 Ti | - | - | Swapped in from Wisteria |
| **NIC** | Silicom PE310G4SPI9L-XR-CX3 | Oct 27, 2024 | $38.52 | 4-Port 10GB SFP+ |

### 🍆 Eggplant - Detailed Component List

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Chassis** | Supermicro 4U 36 Bay | Dec 20, 2024 | $527.38 | TruNAS Storage Server, Xeon 28 core, 64GB |
| **RAM** | 6× Micron 18ASF2G72PZ-2G3B1 + 16× Micron 18ASF1G72PZ-2G1A2 | - | - | 16GB DDR4-2400 + 8GB DDR4-2133 ECC RDIMM, 224GB, 22 of 24 slots |
| **HBA** | 2× Supermicro AOC-S3008L-L8E | Dec 20, 2024 | $18.71 | SAS3 12Gbps 8-port internal PCIe 3.0 |
| **HBA** | LSI SAS9207-8e | Jun 5, 2024 | $27.50 | 8-port external 6Gb/s |
| **Backup SSD** | Crucial MX500 2TB | May 29, 2024 | $176.47 | SATA SSD |
| **ZFS ZIL** | Radian RMS-200/8G | Jun 16, 2024 | $57.00 | PCIe x8 Gen3 NVRAM accelerator |

### Unclustered Automation Node

#### 🪲 leaf-cutter
- **CPU**: Intel i7-4720HQ (8 threads @ 3.6GHz)
- **RAM**: 16GB (2×8GB DDR3)
- **Purpose**: Critical automation fallback when cluster fails ("ant-parade's stunt double")

## Storage Expansion

### NetApp Flash Shelf (Connected to Eggplant)

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **Flash Shelf** | NetApp DS2246 | May 21, 2024 | $158.54 | 24× 2.5" SAS bays, 2× IOM6 controllers |
| **Rails** | NetApp X5526A-R6 | May 24, 2024 | $50.65 | Universal rackmount rail kit |

**Use Case**: Backup target attached to Eggplant node

## Workstations & Desktop Systems

### 🎮 Glicynia (Gaming)

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **CPU** | AMD Ryzen 7 5800X3D | Aug 30, 2024 | $337.07 | 8C/16T, 4.5 GHz boost |
| **RAM** | 64-128GB DDR4 ECC 3200MHz | - | - | |
| **GPU** | AMD Radeon RX 7900 XTX | - | - | |
| **PSU** | Corsair HX1200 | Mar 11, 2022 | $269.73 | 1200W 80+ Platinum, fully modular |

### 💼 Wisteria (Workstation)

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| **CPU** | AMD Ryzen 9 5950X | Dec 23, 2022 | $546.67 | 16C/32T, 4th gen |
| **RAM** | NEMIX 64GB DDR4 ECC 3200MHz | Feb 5, 2022 | $402.60 | 2×32GB PC4-25600 CL22 |
| **GPU** | NVIDIA GTX 980 Ti | - | - | Primary GPU, swapped in from Dragonfruit |
| **GPU** | NVIDIA GTX 1080 Ti | - | - | Secondary GPU |
| **PSU** | Corsair RM750e | Apr 16, 2023 | $110.29 | 750W 80+ Gold, ATX 3.0/PCIe 5.0 |
| **Keyboard** | Corsair K95 RGB Platinum | Aug 11, 2024 | $55.04 | Cherry MX Speed, main workstation |
| **Keyboard** | Corsair K95 RGB Platinum | Aug 16, 2024 | $88.07 | Cherry MX Brown, USB passthrough to Glicynia |

## Rack Infrastructure

### Rack Enclosure
- **Model**: Compaq 42U (9000 series)
- **Cost**: -
- **Notes**: Primary datacenter rack

### UPS Rails
- **Model**: APC SC 870-1250B L / SC 870-1251B R
- **Cost**: $44.03 (Dec 4, 2024)
- **Notes**: Server rackmount sliding rail kit for UPS

## Miscellaneous Lab Equipment

### HBA Cables

| Component | Type | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| EMC Amphenol Mini-SAS | SFF-8088 to SFF-8088 | May 23, 2024 | $11.01 | 2 meter cable |
| Internal Mini SAS | SFF-8087 to SFF-8087 | May 23, 2024 | $19.44 | 0.5-1 meter, 2 pack |
| External SAS | QSFP SFF-8436 to SFF-8088 | Jun 8, 2024 | $30.71 | For NetApp DS4243/DS4246 |

### HBA Adapters & Misc

| Component | Part | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| HBA Adapter | Dual Port Mini SAS SFF-8088 to SFF-8087 | May 23, 2024 | $28.60 | With PCI bracket |
| JBOD Power Board | CSE-PTJBOD-CB2 | May 23, 2024 | $52.85 | Control/power board for JBOD |
| Rails | 2× iStarUSA TC-RAIL-26 | Aug 11, 2024 | $75.13 | 26" sliding rails |

### Brackets

| Component | Type | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| NIC Bracket | Height bracket for PE310G4SPI9L | Oct 27, 2024 | $5.91 | Full height |
| SSD Bracket | Full height for PM1725/F320 | Nov 26, 2024 | $6.61 | PCIe SSD bracket |

### Drive Caddies

| Component | Type | Purchase Date | Cost | Notes |
|-----------|------|---------------|------|-------|
| Supermicro SB16105 | 2.5" SAS/SATA caddy/tray | Dec 23, 2024 | $10.13 | Server drive caddy |
| Supermicro 3.5" Caddy | Lot of 10 | Dec 30, 2024 | $32.97 | Drive tray cage |

## Networking Equipment

### Switches

| Device | Type | Ports | Purchase Date | Cost | Notes |
|--------|------|-------|---------------|------|-------|
| MikroTik CRS317-1G-16S+RM | Cloud Router Switch | 16x SFP+ (10G), 1x GbE | Mar 21, 2025 | $330.29 | Rack mountable, manageable |
| MikroTik CRS310-8G+2S+IN | Cloud Router Switch | 8x 2.5GbE, 2x SFP+ (10G) | Mar 21, 2024 | $211.34 | 2.5/10 Gigabit combo switch |
| TP-Link TL-SG1016PE | Easy Smart Managed | 16x GbE (8 PoE+ @150W) | Sep 15, 2023 | $164.04 | PoE switch, QoS/VLAN/IGMP/LAG |

### Power

| Device | Type | Capacity | Purchase Date | Cost | Status | Notes |
|--------|------|----------|---------------|------|--------|-------|
| Eaton Network M2 5PX3000RT2U | UPS | 3000VA | Dec 2, 2024 | $352.30 | Delivered | Rackmount, tested good condition |
